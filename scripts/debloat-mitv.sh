#!/bin/sh
#
# debloat-mitv.sh — Débloat + installation d'un launcher pour Xiaomi Mi TV A Pro (Google TV)
#
# Écrit en POSIX sh (compatible BusyBox ash) pour tourner DANS le conteneur ADB.
# Toutes les désinstallations utilisent `pm uninstall --user 0` : RÉVERSIBLE
# (réinstallable via `cmd package install-existing <pkg>` ou une réinit usine),
# rien n'est supprimé de la partition système.
#
# ── Utilisation (depuis l'hôte) ──────────────────────────────────────────────
#   1. Active le débogage réseau sur la TV.
#   2. Lance le conteneur :   docker run -d --name adb --network host ghcr.io/mrmeganova/adb-docker
#   3. Copie le script :      docker cp debloat-mitv.sh adb:/tmp/
#   4. Dry-run (n'exécute rien, -it requis pour les confirmations) :
#        docker exec -it adb sh /tmp/debloat-mitv.sh <IP_TV>
#      Appliquer :
#        docker exec -it adb sh /tmp/debloat-mitv.sh <IP_TV> --apply
#
#   Variable d'env :
#     ADB   commande adb (défaut: "adb" car on est dans le conteneur).
#           Pour piloter depuis l'hôte : ADB="docker exec adb adb"
#     LAUNCHER_APK  chemin d'un APK de launcher à sideloader (ex: Projectivy).
#
# ── Sous-commandes ───────────────────────────────────────────────────────────
#     <IP> --apply       débloat (confirmation par catégorie)
#     <IP> --launcher    installe Projectivy (sideload si LAUNCHER_APK)
#     <IP> --set-home    met Projectivy par défaut (désactive le launcher système)
#     <IP> --restore     réinstalle les paquets retirés par ce script
#
set -eu

TV_IP="${1:-}"
MODE="${2:-dry-run}"
ADB="${ADB:-adb}"
LAUNCHER_PKG="com.spocky.projengmenu"          # Projectivy Launcher
LAUNCHER_ACT="com.spocky.projengmenu.ui.home.MainActivity"  # activité Home de Projectivy
STOCK_LAUNCHER="com.google.android.apps.tv.launcherx"
LOG="/tmp/debloat-removed.log"                 # trace des paquets retirés (pour --restore)

if [ -z "$TV_IP" ]; then
  echo "Usage: $0 <IP_TV> [--apply|--launcher|--set-home|--restore] [--apply]" >&2
  exit 1
fi

# --apply peut être en 2e OU 3e position (ex: --set-home --apply). On le détecte partout.
APPLY=0
for arg in "$@"; do
  [ "$arg" = "--apply" ] && APPLY=1
done

# ── Listes de paquets (issues de TON installed_packages) ─────────────────────
# Listes en texte simple (un paquet par ligne) : itérables avec `for ... in $LIST`.

# Bloat Xiaomi : pubs, télémétrie, doublons, apps inutiles — sans risque.
SAFE="
com.miui.tv.analytics
com.xiaomi.statistic
com.xiaomi.tvqs.overseas
com.mitv.tvhome.michannel
com.mitv.tvhome.mitvplus
com.mitv.tvhome.oemtab
com.mitv.toolhouse
com.mitv.gallery
com.xiaomi.mimusic2
com.xiaomi.mitv.manualhelp
com.xiaomi.mitv.mediaexplorer
com.xiaomi.mitv.smartshare
com.xiaomi.mitv.scenemode
com.xm.webcontent
com.xiaomo.tv.milegal
fusion.android.tv.demo
"

# Apps de streaming préinstallées — retire celles que tu n'utilises pas.
# (commente une ligne pour la garder : préfixe par # ne marche PAS ici,
#  supprime carrément la ligne du bloc pour conserver l'app)
STREAMING="
com.amazon.amazonvideo.livingroom
com.disney.disneyplus
com.netflix.ninja
com.plexapp.android
com.spotify.tv.android
com.google.android.youtube.tvmusic
com.google.android.videos
com.google.android.play.games
com.google.android.youtube.tv
"

# Apps régionales FR préinstallées.
FRENCH="
com.canal.android.canal
fr.francetv.pluzz
fr.m6.m6replay
fr.tf1.mytf1
tv.molotov.app
"

# RISQUE MODÉRÉ — casse potentiellement une fonctionnalité :
#   com.google.android.apps.mediashell -> CASSE le "cast" (Chromecast intégré)
#   com.google.android.katniss / tv.assistant -> casse recherche/Assistant vocal
#   com.mitv.tvhome.atv -> overlay home Xiaomi (retirer seulement avec un autre launcher actif)
#   com.mitv.livetv* -> Live TV tuner (retirer si pas d'antenne TNT)
#   com.xiaomi.wfdsinkhelperservice -> Miracast (recopie d'écran)
MODERATE="
com.google.android.apps.mediashell
com.google.android.katniss
com.google.android.tv.assistant
com.google.android.apps.tv.dreamx
com.mitv.tvhome.atv
com.mitv.livetv
com.mitv.livetv.ci_mediatek
com.mitv.videoplayer
com.xiaomi.wfdsinkhelperservice
com.mitv.overseaservice
"

# A NE JAMAIS TOUCHER (pour info) : com.android.*, com.google.android.gms,
#   .gsf, .webview, .permissioncontroller, .packageinstaller, com.android.vending,
#   com.google.android.apps.tv.launcherx, com.android.tv.settings,
#   com.xiaomi.gtv.settings, com.mediatek.tvinput, com.mediatek.tv.service,
#   com.google.android.inputmethod.latin, com.google.android.tts.

# ── Helpers ──────────────────────────────────────────────────────────────────
connect() {
  echo "→ Connexion à $TV_IP:5555 ..."
  $ADB connect "$TV_IP:5555"
  $ADB devices
  echo
}

remove_category() {
  name="$1"
  pkgs="$2"
  count=$(printf '%s\n' "$pkgs" | grep -c . || true)
  echo "════════════════════════════════════════════════════"
  echo "Catégorie : $name ($count paquets)"
  for pkg in $pkgs; do echo "   - $pkg"; done
  printf 'Retirer cette catégorie ? [y/N] '
  read ans || ans=""
  case "$ans" in
    y|Y|o|O) ;;
    *) echo "  (ignorée)"; return 0 ;;
  esac
  for pkg in $pkgs; do
    echo "→ uninstall $pkg"
    if [ "$APPLY" = "1" ]; then
      if $ADB shell pm uninstall --user 0 "$pkg" 2>&1 | grep -q Success; then
        echo "$pkg" >> "$LOG"
        echo "   ✓ retiré"
      else
        echo "   ⚠ échec ou déjà absent"
      fi
    fi
  done
}

debloat() {
  connect
  if [ "$APPLY" != "1" ]; then
    echo "*** DRY-RUN : rien ne sera modifié. Ajoute --apply pour exécuter. ***"
    echo
  fi
  remove_category "Bloat Xiaomi (sûr)"       "$SAFE"
  remove_category "Streaming préinstallé"    "$STREAMING"
  remove_category "Apps FR préinstallées"    "$FRENCH"
  remove_category "Risque modéré (lis bien)" "$MODERATE"
  echo
  echo "Terminé. Paquets retirés consignés dans $LOG"
}

restore() {
  connect
  if [ ! -f "$LOG" ]; then
    echo "Aucun $LOG : rien à restaurer."
    exit 0
  fi
  while read pkg; do
    [ -z "$pkg" ] && continue
    echo "→ restore $pkg"
    [ "$APPLY" = "1" ] && $ADB shell cmd package install-existing "$pkg" || true
  done < "$LOG"
}

launcher() {
  connect
  echo "→ Launcher Projectivy ($LAUNCHER_PKG)"
  if [ -n "${LAUNCHER_APK:-}" ]; then
    echo "  Sideload de $LAUNCHER_APK"
    [ "$APPLY" = "1" ] && $ADB install -r "$LAUNCHER_APK" || true
  else
    echo "  ! Aucun LAUNCHER_APK fourni."
    echo "    Installe Projectivy depuis le Play Store de la TV, OU télécharge l'APK"
    echo "    et relance avec : LAUNCHER_APK=/tmp/projectivy.apk $0 $TV_IP --launcher --apply"
  fi
  echo
  echo "  Pour le mettre PAR DÉFAUT (bouton Home), lance :  $0 $TV_IP --set-home --apply"
}

# Rend Projectivy par défaut : sur Google TV il n'existe AUCUN réglage UI,
# il faut désactiver le(s) launcher(s) système pour que le Home retombe sur Projectivy.
set_home() {
  connect

  # Projectivy est-il bien installé ?
  if ! $ADB shell pm list packages | grep -q "$LAUNCHER_PKG"; then
    echo "✗ Projectivy ($LAUNCHER_PKG) n'est pas installé. Lance d'abord : $0 $TV_IP --launcher"
    exit 1
  fi

  echo "→ Launchers (Home) actuellement enregistrés (priorité décroissante) :"
  $ADB shell cmd package query-activities --brief \
    -a android.intent.action.MAIN -c android.intent.category.HOME | tail -n +2 || true
  echo

  # Méthode 1 (propre) : forcer Projectivy comme home préféré, sans rien désactiver.
  echo "→ Tentative set-home-activity (méthode propre) :"
  if [ "$APPLY" = "1" ]; then
    $ADB shell cmd package set-home-activity \
      "$LAUNCHER_PKG/$LAUNCHER_ACT" 2>&1 || true
  fi
  echo

  # Méthode 2 (repli) : désactiver les homes système de priorité supérieure
  # (launcherx Google + setupwraith RecoveryActivity) pour que Projectivy l'emporte.
  for home in com.google.android.apps.tv.launcherx com.google.android.tungsten.setupwraith com.mitv.tvhome.atv; do
    $ADB shell pm list packages | grep -q "$home" || continue
    echo "→ désactivation du home système : $home"
    if [ "$APPLY" = "1" ]; then
      $ADB shell pm disable-user --user 0 "$home" >/dev/null 2>&1 \
        && { echo "$home" >> "$LOG"; echo "   ✓ désactivé"; } \
        || echo "   ⚠ échec (déjà désactivé ?)"
    fi
  done
  echo

  echo "→ Vérification : launchers Home restants :"
  $ADB shell cmd package query-activities --brief \
    -a android.intent.action.MAIN -c android.intent.category.HOME | tail -n +2 || true
  echo
  echo "Tu dois voir com.spocky.projengmenu en tête (le FallbackHome -1000 est normal)."
  echo "Appuie sur le bouton Home de la télécommande → Projectivy doit s'ouvrir."
  echo "Retour arrière :"
  echo "    $ADB shell pm enable com.google.android.apps.tv.launcherx"
  echo "    $ADB shell pm enable com.google.android.tungsten.setupwraith"
  echo "    $ADB shell pm enable com.mitv.tvhome.atv"
}

# ── Dispatch ─────────────────────────────────────────────────────────────────
case "$MODE" in
  --launcher) launcher ;;
  --set-home) set_home ;;
  --restore)  restore ;;
  --apply|dry-run) debloat ;;
  *) echo "Mode inconnu : $MODE" >&2; exit 1 ;;
esac
