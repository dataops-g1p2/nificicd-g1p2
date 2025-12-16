# Guide Complet de Test du NiFi CI/CD

## Prérequis

Avant de commencer, vérifiez que vous avez :
```bash
# Vérifier Docker
docker --version
docker compose version

# Vérifier les outils nécessaires
make --version
jq --version
curl --version
openssl version
```

##  Étapes de Test Complètes

### **Phase 1 : Configuration Initiale**

#### 1.1 Afficher l'aide
```bash
make help
# Vérifie que toutes les commandes sont listées correctement
```

#### 1.2 Valider l'environnement
```bash
make validate-env
# Vérifie si le fichier .env existe
# Si le fichier n'existe pas, il vous indiquera comment le créer
```

#### 1.3 Créer les fichiers d'environnement (si nécessaire)
```bash
# Si vous n'avez pas de fichier .env
cp .env.template .env
cp .env.template .env.development
cp .env.template .env.staging
cp .env.template .env.production
```

#### 1.4 Générer les mots de passe
```bash
# Pour l'environnement local
make setup-password

# Pour tous les environnements à la fois
make setup-passwords

# Vérifie que les mots de passe sont générés dans les fichiers .env
cat .env | grep NIFI_PASSWORD
cat .env | grep NIFI_SENSITIVE_PROPS_KEY
```

---

### **Phase 2 : Environnement Docker Local**

#### 2.1 Démarrer l'environnement
```bash
make up
# Les conteneurs NiFi et Registry doivent démarrer
# Attendre environ 30 secondes pour l'initialisation
```

#### 2.2 Vérifier le statut
```bash
make status
# Les conteneurs doivent être "Up" avec leurs ports

docker ps
# Vérifier manuellement que les conteneurs tournent
```

#### 2.3 Vérifier la santé des services
```bash
make health-check
# NiFi UI doit répondre (https://localhost:8443/nifi)
# Registry doit répondre (http://localhost:18080/nifi-registry)
```

#### 2.4 Accéder aux informations de connexion
```bash
make echo-info-access
# Affiche username, password et URLs
# Vérifier que les infos correspondent à celles du conteneur
```

#### 2.5 Consulter les logs
```bash
# Logs de tous les conteneurs
make logs
# Ctrl+C pour arrêter

# Logs NiFi uniquement
make logs-nifi

# Logs Registry uniquement
make logs-registry
```

#### 2.6 Tester l'interface web
```bash
# Ouvrir dans le navigateur
open https://localhost:8443/nifi
# ou
xdg-open https://localhost:8443/nifi

# Se connecter avec les credentials affichés par echo-info-access
```

---

### **Phase 3 : Configuration du Registry**

#### 3.1 Setup du Registry (bucket par défaut)
```bash
make setup-registry-default
# Crée un bucket "default" dans le Registry
```

#### 3.2 Vérifier les informations du Registry
```bash
make registry-info
# Affiche les buckets créés
# Liste les flows disponibles dans flows/
```

#### 3.3 Accéder à l'interface Registry
```bash
# Ouvrir dans le navigateur
open http://localhost:18080/nifi-registry
# ou
xdg-open http://localhost:18080/nifi-registry

# Vérifier que les buckets sont visibles dans l'UI
# Explorer l'interface Registry
```

#### 3.4 Setup avec buckets par flow (optionnel)
```bash
# Pour tous les flows
make setup-registry-buckets

# Pour un flow spécifique
make setup-registry-buckets FLOW=MyFlow

# Pour plusieurs flows
make setup-registry-buckets FLOWS=Flow1,Flow2,Flow3
```

#### 3.5 Lister les buckets du Registry
```bash
make list-registry-buckets
# Affiche tous les buckets créés
```

---

### **Phase 3.5 : Configuration UI - Lier NiFi à Registry (CRITIQUE)**

> **ÉTAPE OBLIGATOIRE** : À faire une seule fois par environnement avant tout commit vers Registry

#### 3.5.1 Ouvrir l'interface NiFi
```bash
# L'URL sera affichée par cette commande
make echo-info-access

# Ouvrir dans le navigateur
open https://localhost:8443/nifi
# ou
xdg-open https://localhost:8443/nifi
```

#### 3.5.2 Se connecter à NiFi
- **Username** : Affiché par `make echo-info-access`
- **Password** : Affiché par `make echo-info-access`
- Accepter le certificat auto-signé dans le navigateur

#### 3.5.3 Configurer le Registry Client dans l'UI NiFi

##### Étape 1 : Accéder aux paramètres
1. Cliquer sur le menu **☰** (hamburger) en haut à droite
2. Sélectionner **Controller Settings**
3. Cliquer sur l'onglet **Registry Clients**

##### Étape 2 : Ajouter le Registry Client
1. Cliquer sur le bouton **➕ Add Registry Client** (symbole plus)
2. Une fenêtre de configuration s'ouvre

##### Étape 3 : Renseigner les informations

| Champ | Valeur | Description |
|-------|--------|-------------|
| **Name** | `nifi-registry` | Nom du registry client |
| **URL** | `http://nifi-registry:18080` | URL interne Docker (local) |
| **Description** | `Central NiFi Registry` | Description optionnelle |

**Pour les environnements distants (dev/staging/prod)** :
```
URL pour dev:     http://<VM_DEV_IP>:18080
URL pour staging: http://<VM_STAGING_IP>:18080
URL pour prod:    http://<VM_PROD_IP>:18080
```

##### Étape 4 : Sauvegarder
- Cliquer sur **Apply** ou **Save**
- La fenêtre se ferme

#### 3.5.4 Vérifier la connexion

##### Validation visuelle
1. Le registry `nifi-registry` doit apparaître dans la liste
2. **État** : Doit montrer une icône verte ou "Connected"
3. Pas de message d'erreur rouge

##### Test de connexion
```bash
# Depuis le terminal, vérifier que Registry répond
curl -s http://localhost:18080/nifi-registry-api/buckets | jq '.'

# Doit retourner la liste des buckets
```

##### Dépannage si erreur de connexion

**Problème : "Unable to connect to Registry"**
```bash
# Vérifier que le Registry est bien démarré
make health-check

# Vérifier les logs du Registry
make logs-registry

# Redémarrer si nécessaire
make restart
```

**Problème : "URL incorrecte"**
- Pour environnement local : utilisez `http://nifi-registry:18080`
- Pour environnement distant : utilisez l'IP publique de la VM


---

### **Phase 3.6 : Test du Workflow Complet dans l'UI**

> ** Objectif** : Créer un flow dans NiFi et le committer vers Registry

#### 3.6.1 Créer un Process Group de test

##### Dans l'interface NiFi (https://localhost:8443/nifi)

1. **Glisser-déposer** l'icône **Process Group** sur le canvas
2. **Nommer** le Process Group : `TestFlow-Demo`
3. **Double-cliquer** sur le Process Group pour entrer dedans

#### 3.6.2 Ajouter des composants de test

##### Créer un flow simple :
1. **Ajouter un GenerateFlowFile processor** :
   - Drag & drop l'icône Processor
   - Rechercher "GenerateFlowFile"
   - Configure : Schedule = 10 sec

2. **Ajouter un LogAttribute processor** :
   - Connecter GenerateFlowFile → LogAttribute
   - Configure : Auto-terminate tous les relationships

3. **Démarrer les processors** :
   - Sélectionner les deux processors
   - Clic droit → Start
   - Vérifier qu'aucun bulletin rouge n'apparaît

#### 3.6.3 Versionner le Flow (Commit vers Registry)

##### Étape 1 : Sortir du Process Group
- Cliquer sur "NiFi Flow" dans le breadcrumb en haut

##### Étape 2 : Commencer le versioning
1. **Clic droit** sur le Process Group `TestFlow-Demo`
2. Sélectionner **Version** → **Start version control**

##### Étape 3 : Configuration du commit

Une fenêtre "Save Flow Version" apparaît :

| Champ | Valeur |
|-------|--------|
| **Registry** | `nifi-registry` (celui configuré avant) |
| **Bucket** | `default` (ou choisir un bucket spécifique) |
| **Flow Name** | `TestFlow-Demo` |
| **Flow Description** | `Test flow for validation` |
| **Comments** | `Initial commit - testing registry integration` |

##### Étape 4 : Sauvegarder
- Cliquer sur **Save**
- Une icône verte doit apparaître sur le Process Group

#### 3.6.4 Vérifier dans Registry UI

##### Accéder au Registry
```bash
open http://localhost:18080/nifi-registry
```

##### Validation visuelle
1. Aller dans **Buckets** → `default`
2. Le flow **TestFlow-Demo** doit apparaître
3. Cliquer dessus pour voir :
   - Version : 1
   - Commentaire : "Initial commit..."
   - Date de création

#### 3.6.5 Faire un deuxième commit (test de versioning)

##### Dans NiFi UI
1. **Entrer** dans le Process Group `TestFlow-Demo`
2. **Modifier** quelque chose :
   - Ajouter un nouveau processor (ex: UpdateAttribute)
   - Ou modifier un paramètre
3. **Sortir** du Process Group

##### Committer les changements
1. **Clic droit** sur le Process Group
2. **Version** → **Commit local changes**
3. Renseigner :
   - **Comments** : `Added UpdateAttribute processor`
4. **Save**

##### Vérifier dans Registry
```bash
# Via CLI
make list-registry-versions

# Via UI Registry
# Voir que TestFlow-Demo a maintenant 2 versions
```
---

### **Phase 4 : Gestion des Flows**

#### 4.1 Lister les flows disponibles
```bash
make list-flows
# Liste tous les flows/
```

#### 4.2 Importer des flows dans le Registry

```bash
# Import automatique de tous les flows
make import-flows-auto

# Import d'un flow spécifique
make import-flow FLOW=MonFlow

# Import avec pattern
make import-flows-pattern PATTERN=prod*
```

#### 4.3 Vérifier les flows dans le Registry
```bash
# Lister les flows dans les buckets
make list-registry-flows

# Voir tous les IDs (buckets + flows + versions)
make show-registry-ids

# Lister les versions
make list-registry-versions
```

#### 4.4 Exporter des flows depuis le Registry

```bash
# Export interactif d'un flow
make export-flow-from-registry

# Export de tous les flows
make export-flows-from-registry

# Export par ID spécifique
make export-flow-by-id BUCKET_ID=xxx FLOW_ID=yyy
```

---

### **Phase 5 : Gestion de l'Environnement**

#### 5.1 Redémarrer l'environnement
```bash
make restart
# Arrête et redémarre tous les conteneurs
```

#### 5.2 Arrêter l'environnement
```bash
make down
# Arrête tous les conteneurs
```

#### 5.3 Nettoyer les volumes (Supprime les données)
```bash
make clean-volumes
# Supprime les volumes Docker (données perdues)
```

#### 5.4 Nettoyage complet (Dangereux)
```bash
make prune
# Nettoie tout le système Docker
# Confirmer avec 'y'
```

---

### **Phase 6 : Multi-Environnements**

#### 6.1 Valider un environnement spécifique
```bash
make validate-env ENV=dev
make validate-env ENV=staging
make validate-env ENV=prod
```

#### 6.2 Afficher les infos d'accès pour chaque environnement
```bash
make echo-info-access ENV=dev
make echo-info-access ENV=staging
make echo-info-access ENV=prod

# Ou tous à la fois
make echo-info-access-all
```

#### 6.3 Nettoyer les infos générées
```bash
# Pour un environnement
make clean-generated-info ENV=dev

# Pour tous
make clean-generated-info-all
```

---

### **Phase 7 : Accès SSH aux VMs (Environnements Cloud)**

```bash
# Connexion SSH aux différents environnements
make ssh-dev
make ssh-staging
make ssh-prod

# Nécessite que les clés SSH soient configurées
```
---

## Checklist de Validation

### Commandes de Base
- `make help` affiche toutes les commandes
- `make validate-env` vérifie la configuration
- `make setup-password` génère les credentials

### Docker Local
- `make up` démarre les conteneurs
- `make status` montre les conteneurs actifs
- `make health-check` confirme que tout fonctionne
- `make logs` affiche les logs
- `make down` arrête les conteneurs

### Registry
- `make setup-registry-default` crée le bucket
- `make registry-info` affiche les infos
- `make list-registry-buckets` liste les buckets
- **UI Registry accessible** (http://localhost:18080/nifi-registry)
- **Buckets visibles dans l'UI Registry**

### Flows
- `make list-flows` liste les flows locaux
- `make import-flows-auto` importe dans Registry
- `make export-flows-from-registry` exporte depuis Registry
- `make list-registry-flows` liste les flows du Registry


### Multi-env
- `make echo-info-access ENV=dev` fonctionne
- `make clean-generated-info ENV=dev` nettoie
- `make setup-passwords` configure tous les envs

---
