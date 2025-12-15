# --- CONFIGURATION ---
$registryUrl  = "http://localhost:18080/nifi-registry-api"
$bucketId     = "f7050713-f1ae-4ab8-9cb4-33fcc1d80b10"
$outputFolder = "C:\Users\pc gold\nificicd-g1p2\nifi\flows"

# Création du dossier si n'existe pas
if (!(Test-Path $outputFolder)) {
    New-Item -ItemType Directory -Path $outputFolder | Out-Null
}

Write-Host "`n---- EXPORT DE TOUS LES FLOWS DU BUCKET ----`n"

# Récupérer tous les flows du bucket
$flowsUrl = "$registryUrl/buckets/$bucketId/flows"

try {
    $flows = Invoke-RestMethod -Uri $flowsUrl -Method GET
} catch {
    Write-Host "Erreur : impossible de recuperer les flows du bucket !"
    Write-Host $_.Exception.Message
    exit
}

if ($flows.Count -eq 0) {
    Write-Host "Aucun flow trouve dans ce bucket."
    exit
}

Write-Host "Nombre de flows trouves : $($flows.Count)`n"

# Exporter la dernière version de chaque flow
foreach ($flow in $flows) {

    $flowId = $flow.identifier
    $flowName = $flow.name.Replace(" ", "_")

    Write-Host " Flow : $flowName (ID : $flowId)"

    # URL des versions
    $versionsUrl = "$registryUrl/buckets/$bucketId/flows/$flowId/versions"

    try {
        $versions = Invoke-RestMethod -Uri $versionsUrl -Method GET
    } catch {
        Write-Host " Impossible de recuperer les versions !"
        continue
    }

    if ($versions.Count -eq 0) {
        Write-Host "  Aucune version trouvee."
        continue
    }

    # Dernière version
    $latestVersion = ($versions | Sort-Object version -Descending | Select-Object -First 1).version
    Write-Host "   Derniere version : $latestVersion"

    # Télécharger le contenu
    $downloadUrl = "$registryUrl/buckets/$bucketId/flows/$flowId/versions/$latestVersion/export"

    try {
        $flowContent = Invoke-RestMethod -Uri $downloadUrl -Method GET
    } catch {
        Write-Host " Erreur lors du telechargement !"
        continue
    }

    # Fichier de sortie
    $outputFile = Join-Path $outputFolder "$flowName-latest.json"

    # Sauvegarde
    $flowContent | ConvertTo-Json -Depth 100 | Out-File $outputFile -Encoding utf8

    Write-Host "   Flow exporte dans : $outputFile`n"
}

Write-Host "---- EXPORT TERMINE ----"
