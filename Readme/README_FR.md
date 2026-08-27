<p align="center">
  <img src="../screens/logo.png" alt="macSSH Logo" width="160"/>
</p>

<h1 align="center">macSSH</h1>

<p align="center">
  <strong>Gestionnaire de connexions SSH, navigateur SFTP double panneau, émulateur de terminal et proxy SOCKS5 dynamique 100% natif pour macOS</strong>
</p>

<p align="center">
  <em>Pur Swift & SwiftUI • Binaire Universel (Apple Silicon & Intel)</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15.0%2B%20(Sequoia%20%7C%20Tahoe)-black?style=flat-square&logo=apple" alt="macOS 15.0+ (Sequoia | Tahoe)"/>
  <img src="https://img.shields.io/badge/Swift-5.9%2B%20%7C%206.0-orange?style=flat-square&logo=swift" alt="Swift 5.9+ / 6.0"/>
  <img src="https://img.shields.io/badge/Architecture-Universal%20(arm64%20%2B%20x86__64)-purple?style=flat-square" alt="Universal Binary"/>
  <a href="../LICENSE"><img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License MIT"/></a>
</p>

---

<p align="center">
  🌐 <strong>Languages / 多语言 / Ngôn ngữ / Языки / Langues</strong>
</p>

<p align="center">
  <a href="../README.md">English</a> •
  <a href="README_VI.md">Tiếng Việt</a> •
  <a href="README_ZH_CN.md">简体中文</a> •
  <a href="README_ZH_TW.md">繁體中文</a> •
  <a href="README_RU.md">Русский</a> •
  <strong>Français</strong>
</p>

---

## ⚠️ Important : Conçu exclusivement pour macOS (macOS Only)

> [!IMPORTANT]
> **macSSH est conçu spécifiquement pour Apple macOS.**
> Il s'agit d'une application 100% native développée avec **SwiftUI**, **AppKit**, **SwiftData** et les frameworks de sécurité Apple **LocalAuthentication (Touch ID)** et **Keychain**.
> 
> L'application **NE prend PAS en charge** Windows ni Linux — garantissant une réactivité native instantanée, une latence nulle et une empreinte mémoire minimale.

---

## 🌟 Présentation du projet

**macSSH** fournit une solution complète et native pour les développeurs, ingénieurs DevOps et administrateurs système gérant des serveurs distants sur Mac :

- **Navigateur SFTP double panneau (Dual-Pane)** : Glisser-déposer (Drag & Drop) bidirectionnel intuitif entre les panneaux local et distant, avec glisser-déposer direct vers le Finder de macOS.
- **Terminal SSH haute performance** : Émulateur de terminal fluide `xterm-256color` basé sur SwiftTerm (60 FPS), flux direct de frappe sans latence (Zero-latency Direct Feed) et lancement direct dans l'application native `Terminal.app` de macOS en 1 clic.
- **Proxy SOCKS5 dynamique via tunnel SSH** : Serveur proxy SOCKS5 intégré routé via la session SSH. Prise en charge de Localhost (`127.0.0.1`) ou du partage sur tout le réseau local (`0.0.0.0`) avec bascule rapide et résolution intelligente des conflits de ports.
- **Éditeur externe « Ouvrir avec » et synchronisation automatique** : Ouvrez vos fichiers distants dans n'importe quel éditeur macOS (VS Code, TextEdit, Xcode, etc.) et enregistrez (`⌘S`) pour téléverser et remplacer automatiquement sur le serveur.
- **Présence dans la barre de menus et exécution en arrière-plan** : Reste accessible dans la barre de menus de macOS, maintenant vos tunnels SSH et proxies actifs même après la fermeture de toutes les fenêtres.
- **Configuration autonome et sécurité** : Export/import de configurations au format JSON, mémorisation du dernier fichier utilisé, verrouillage par Touch ID et chiffrement matériel des mots de passe en AES-256-GCM.

---

## ✨ Fonctionnalités clés

### 🌐 1. Proxy SOCKS5 dynamique (SSH Tunnel)
- **Tunnel proxy automatique** : Démarre un serveur proxy SOCKS5 routant le trafic réseau via la connexion SSH active.
- **Partage local et réseau (LAN)** : Écoute sur `127.0.0.1` (ce Mac uniquement) ou `0.0.0.0` (partage avec les autres appareils du réseau local avec affichage automatique de l'adresse IP).
- **Badge d'activation rapide** : Badge violet SOCKS5 sur chaque ligne de serveur permettant d'activer ou de désactiver le proxy en un clic.
- **Gestion des conflits de ports** : Si le port est déjà utilisé (`Address already in use`), macSSH désactive le proxy en toute sécurité et affiche une notification Toast de 5 secondes sans interrompre la session SSH principale.

### 📂 2. Navigateur SFTP double panneau et glisser-déposer
- **Disposition double panneau** : Panneau local (Mac) à gauche et panneau distant (serveur) à droite.
- **Glisser-déposer bidirectionnel** :
  - Glissez des fichiers/dossiers du panneau local vers le distant pour les téléverser.
  - Glissez du distant vers le local (ou vers un sous-dossier) pour les télécharger instantanément.
  - Glissez directement des fichiers distants vers le **Finder de macOS** via `NSFilePromiseProvider`.
- **Téléchargement récursif de dossiers** : Crée automatiquement l'arborescence complète et télécharge tous les sous-dossiers.
- **Barre de saisie directe du chemin** : Saisissez ou collez des chemins absolus (`/var/www`, `~/.config`) avec les raccourcis `⌘L` ou `⇧⌘G`.
- **Confirmation d'écrasement sécurisée** : Boîte de dialogue native `NSAlert` pour choisir « Remplacer (Replace) » ou « Annuler (Cancel) ».
- **Interface optimisée** : Suppression des barres de défilement horizontal, ajustement dynamique des colonnes et suppression groupée.

### 📝 3. Éditeur externe « Ouvrir avec » et synchronisation lors de la sauvegarde
- **Ouvrir avec n'importe quelle application Mac** : Menu contextuel `Open With Default App` et `Open With…` (détecte VS Code, Xcode, Sublime Text, TextEdit, etc.).
- **Téléversement automatique sur `⌘S`** : Surveillance par timer (cycle de 2s). Dès que vous appuyez sur Enregistrer (`⌘S`) dans votre éditeur, le fichier modifié est renvoyé directement sur le serveur distant avec journalisation en direct.

### 💻 4. Terminal SSH fluide et sans latence
- **Émulateur SwiftTerm** : Rendu fluide à 60 FPS, prise en charge complète du standard `xterm-256color`.
- **Zero-Latency Direct Feed** : Modes OpenSSH PTY avec flux direct sur le thread principal pour éliminer tout délai de saisie au clavier.
- **Lancement dans le terminal natif de macOS** : Bouton **« Open in macOS Terminal »** ouvrant la session SSH dans l'application `Terminal.app` via AppleScript.
- **Feuille de saisie de mot de passe** : Détection automatique des erreurs d'authentification et affichage d'une feuille pour ressaisir facilement vos identifiants.

### 📊 5. Gestionnaire de transferts et console de journalisation
- **Panneau inférieur à 3 onglets** :
  - 📤 **File d'attente d'envoi (Upload Queue)** : Affiche la progression en %, le volume transféré, **la vitesse en temps réel (MB/s, KB/s)**, **le temps restant estimé (ETA)** et un bouton d'annulation.
  - 📥 **File d'attente de téléchargement (Download Queue)** : Suivi en direct du téléchargement des fichiers.
  - 📜 **Console de logs (Log Console)** : Flux des opérations SFTP horodaté `[HH:mm:ss]` avec coloration par niveau (`[INFO]`, `[SUCCESS]`, `[WARN]`, `[ERROR]`).
- **Fonctionnement en mémoire vive** : Les données de transfert et de journalisation ne sont conservées qu'en RAM pendant la session et libérées à la fermeture de la fenêtre.

### 🗂️ 6. Disposition élégante à 2 colonnes
- **Structure 2 colonnes** : Barre latérale (Dossiers, Réglages, Dons, À propos) et liste des connexions.
- **Glisser-déposer entre colonnes** : Classez vos serveurs en les faisant glisser directement dans les dossiers de la barre latérale.
- **Connexion rapide par double-clic** : Double-cliquez sur un serveur pour vous connecter et ouvrir le navigateur de fichiers.
- **Indicateur de statut en temps réel** : Pastille verte indiquant instantanément la connexion active.
- **Boutons d'action rapide** : Boutons toujours visibles pour ouvrir le navigateur SFTP 📁 et le terminal `>_` sur chaque ligne.

### 💾 7. Configuration autonome et sécurité biométrique
- **Fichiers de configuration JSON** : Enregistrer (`⌘S`), Enregistrer sous (`⇧⌘S`), Ouvrir (`⌘O`), Nouvelle configuration (`⌘⌥N`).
- **Mémorisation automatique** : Réouvre automatiquement le dernier fichier de configuration au démarrage.
- **Avertissement de fermeture** : Alerte de sauvegarde lors de la fermeture avec modifications non enregistrées.
- **Chiffrement AES-256-GCM** : Les mots de passe peuvent être chiffrés et enregistrés dans la configuration sans dépendre du trousseau Keychain.
- **Verrouillage par Touch ID** : Protégez l'accès à l'application avec Touch ID ou le mot de passe de votre Mac.

### 🌐 8. Architecture multilingue (L10N)
- Prise en charge multilingue intégrée avec mécanisme de repli (Fallback) automatique en anglais :
  - 🇬🇧 Anglais (**English** - repli par défaut)
  - 🇻🇳 Vietnamien (**Tiếng Việt**)
  - 🇨🇳 Chinois simplifié (**简体中文**)
  - 🇹🇼 Chinois traditionnel (**繁體中文**)
  - 🇷🇺 Russe (**Русский**)
  - 🇫🇷 **Français**
- Changement de langue instantané dans les Réglages sans redémarrage de l'application.

---

## 📸 Captures d'écran (Screenshots)

| Gestionnaire de connexions | Menu contextuel et actions |
|:---:|:---:|
| ![Connection Manager](../screens/screen-1.png) | ![Context Menu](../screens/screen-2.png) |
| *Interface épurée à 2 colonnes, gestion par dossiers, connexion rapide* | *Menu clic-droit : proxy SOCKS5, Terminal, explorateur SFTP* |

| Explorateur SFTP double panneau & File d'attente | Terminal SSH intégré |
|:---:|:---:|
| ![File Browser](../screens/screen-3.png) | ![SSH Terminal](../screens/screen-4.png) |
| *Glisser-déposer bidirectionnel, barre de chemin direct, vitesse et ETA* | *Émulateur xterm-256color sans latence* |

---

## 💽 Installation et Configuration (Installation & Setup)

### Configuration requise
- **macOS** : 15.0+ (Sequoia | Tahoe).
- **Architecture** : Universal 2 (Optimisé pour **Apple Silicon M1/M2/M3/M4** et **Intel x86_64**).

### 1. Téléchargement du DMG
Téléchargez la dernière version `macSSH_Universal_x.x.x.dmg` depuis les [GitHub Releases](https://github.com/devduong/macSSH/releases).

### 2. Installation de l'application
Ouvrez le fichier `.dmg` et glissez **macSSH.app** dans votre dossier **Applications** (`/Applications`).

### 3. Premier lancement et contournement de macOS Gatekeeper

> [!WARNING]
> **Avertissement (Warning)**  
> Comme macSSH est un projet open-source gratuit sans certificat payant Apple Developer, la sécurité macOS Gatekeeper peut afficher un message : *« Impossible d'ouvrir macSSH car l'identité du développeur ne peut être vérifiée »* ou *« macOS ne peut pas vérifier que cette application est exempte de logiciels malveillants »*.

Pour ouvrir l'application :
1. Ouvrez les **Réglages Système (System Settings)** sur votre Mac.
2. Rendez-vous dans **Confidentialité et sécurité (Privacy & Security)**.
3. Faites défiler jusqu'à la section **Sécurité (Security)**.
4. Cliquez sur le bouton **« Ouvrir quand même (Open Anyway) »** à côté de la notification indiquant que macSSH a été bloqué.
5. Dans la boîte de dialogue de confirmation, cliquez sur **« Ouvrir (Open) »** et saisissez votre mot de passe Mac ou utilisez Touch ID.

*(Méthode alternative : faites un clic droit / Contrôle-clic sur `macSSH.app` dans le Finder -> sélectionnez **Ouvrir (Open)** -> cliquez sur **Ouvrir**).*

---

### Compilation à partir des sources

#### Prérequis
- **Xcode** : 16.0 ou ultérieur.
- **macOS SDK** : 15.0 ou ultérieur.
- **Swift** : 5.9+.

#### Étapes de compilation

1. **Cloner le dépôt** :
   ```bash
   git clone https://github.com/devduong/macSSH.git
   cd macSSH
   ```

2. **Ouvrir le projet dans Xcode** :
   ```bash
   open macSSH.xcodeproj
   ```

3. **Compiler l'application** :
   ```bash
   xcodebuild -project macSSH.xcodeproj -scheme macSSH -configuration Release build
   ```
   *Ou sélectionnez le schéma `macSSH` dans Xcode et appuyez sur `Cmd + B`.*

4. **Lancer l'application compilée** :
   ```bash
   open $(xcodebuild -project macSSH.xcodeproj -scheme macSSH -configuration Release -showBuildSettings | grep -m 1 "BUILT_PRODUCTS_DIR" | awk '{print $3}')/macSSH.app
   ```
   *Ou appuyez sur `Cmd + R` pour lancer directement depuis Xcode.*

---

## ☕ Soutenir le projet (Dons)

**macSSH** est un logiciel libre et gratuit. Si macSSH vous est utile au quotidien, n'hésitez pas à offrir un café à l'auteur pour encourager le développement continu ! ❤️

### 1. Soutien via Ko-fi et GitHub
- ☕ **Faire un don sur Ko-fi** : [https://ko-fi.com/X4P324ZPZ3](https://ko-fi.com/X4P324ZPZ3)
- ⭐ **Ajouter une étoile sur GitHub** : [devduong/macSSH](https://github.com/devduong/macSSH)

### 2. Don en cryptomonnaie (Crypto Donation)
Vous pouvez envoyer des jetons compatibles avec le réseau **BNB Smart Chain (BEP20)** (*USDT, BNB, BUSD, USDC, etc.*) à l'adresse de portefeuille ci-dessous :

- **Réseau (Network)** : `BEP20 (BSC – Binance Smart Chain)`
- **Adresse du portefeuille (Wallet Address)** :
  ```text
  0xe26c0DC422EF744816Ca3B2d210e6214fdC4e18E
  ```

---

## 🙏 Remerciements et Crédits (Acknowledgments)

- 🌟 **Un immense merci à [macnev2013](https://github.com/macnev2013)** — L'auteur de `macSCP` et `anySCP`. Merci infiniment pour ses superbes idées initiales et la base du projet qui ont grandement inspiré la conception de **macSSH**.
- 🚀 [Citadel](https://github.com/Orlandos-nl/Citadel) (Joannis Orlandos) & [SwiftNIO SSH](https://github.com/apple/swift-nio-ssh) (Apple) — Bibliothèques fondamentales pour les protocoles SSH & SFTP.
- 💻 [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (Miguel de Icaza) — Puissante bibliothèque d'émulation de terminal pour macOS.
- 🎨 [SF Symbols](https://developer.apple.com/sf-symbols/) (Apple) — Système officiel d'icônes et de symboles macOS.

---

## 📄 Licence (License)

Ce projet est distribué sous licence libre **MIT License** — consultez le fichier [LICENSE](../LICENSE) pour plus d'informations.

---

<p align="center">
  Créé avec ❤️ pour la communauté macOS.
</p>
