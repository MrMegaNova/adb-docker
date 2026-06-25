# scripts

Scripts de **debloat** et de **configuration** pour appareils Android (TV et smartphone),
à exécuter via ADB — généralement depuis le conteneur [adb-docker](../README.md).

Tous les scripts privilégient des opérations **réversibles** : les désinstallations se font
avec `pm uninstall --user 0` (réinstallable via `cmd package install-existing` ou une réinit
usine), rien n'est supprimé de la partition système.

## Pré-requis

1. Activer le **débogage ADB** sur l'appareil :
   - **TV (Google TV / Android TV)** : Paramètres → Système → À propos → cliquer 7× sur
     « Version », puis Paramètres → Système → Options pour les développeurs → activer
     « Débogage réseau » (ADB réseau).
   - **Smartphone** : Paramètres → À propos → taper 7× sur « Numéro de build », puis
     Options pour les développeurs → activer « Débogage USB » (ou réseau).
2. Lancer le conteneur ADB :
   ```sh
   docker run -d --name adb --network host ghcr.io/mrmeganova/adb-docker
   ```
3. Copier le script dans le conteneur puis l'exécuter (voir chaque script ci-dessous).

> Astuce : la plupart des scripts tournent **dans** le conteneur (POSIX `sh` / BusyBox).
> Pour piloter depuis l'hôte à la place, exporte `ADB="docker exec adb adb"`.

## Scripts disponibles

### `debloat-mitv.sh` — Xiaomi Mi TV A Pro (Google TV)

Débloat (pubs, télémétrie, doublons, streaming/apps régionales préinstallés) et installation
optionnelle d'un launcher alternatif (Projectivy). Les paquets retirés sont consignés dans
`/tmp/debloat-removed.log` pour permettre un `--restore`.

```sh
# Copier le script dans le conteneur
docker cp scripts/debloat-mitv.sh adb:/tmp/

# Dry-run (n'exécute rien, -it requis pour les confirmations)
docker exec -it adb sh /tmp/debloat-mitv.sh <IP_TV>

# Appliquer le débloat (confirmation par catégorie)
docker exec -it adb sh /tmp/debloat-mitv.sh <IP_TV> --apply
```

Sous-commandes :

| Commande | Effet |
|----------|-------|
| `<IP> --apply`    | Débloat, confirmation par catégorie |
| `<IP> --launcher` | Installe Projectivy (sideload si `LAUNCHER_APK` est fourni) |
| `<IP> --set-home` | Met Projectivy par défaut (désactive le launcher système) |
| `<IP> --restore`  | Réinstalle les paquets retirés par ce script |

Le flag `--apply` peut être combiné, ex. : `<IP> --set-home --apply`.

## Ajouter un script

Place ton script ici, garde-le **idempotent** et **réversible** quand c'est possible,
documente l'usage en tête de fichier, puis ajoute une entrée dans la section
« Scripts disponibles » ci-dessus.
