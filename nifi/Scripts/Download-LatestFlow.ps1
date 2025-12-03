# --- CONFIGURATION ---
$registryUrl = "http://localhost:18080/nifi-registry-api"

# Tes vrais IDs
$bucketId = "f7050713-f1ae-4ab8-9cb4-33fcc1d80b10"
$flowId   = "46c54cd9-1e22-4fad-9c97-bf6d4e25cb16"

# Dossier où sauvegarder le flow
$outputFolder = "C:\Users\pc gold\nificicd-g1p2\nifi\flows"
$outputFile   = Join-Path $outputFolder "latest-flow.json"

Write-Host "Recherche de la derniere version du flow..."

# ---- Récupérer toutes les versions ----
$versionsUrl = "$registryUrl/buckets/$bucketId/flows/$flowId/versions"

try {
    $versionsResponse = Invoke-RestMethod -Uri $versionsUrl -Method GET
} catch {
    Write-Host " Erreur : impossible de recuperer les versions du flow !"
    Write-Host $_.Exception.Message
    exit
}

if (-not $versionsResponse | Select-Object) {
    Write-Host " Aucun snapshot trouve !"
    exit
}

# ---- Prendre la derniere version ----
$latestVersion = ($versionsResponse | Sort-Object version -Descending | Select-Object -First 1).version
Write-Host "Derniere version trouvee : $latestVersion"

# ---- Télécharger le contenu ----
$downloadUrl = "$registryUrl/buckets/$bucketId/flows/$flowId/versions/$latestVersion/export"

try {
    $flowContent = Invoke-RestMethod -Uri $downloadUrl -Method GET
} catch {
    Write-Host " Erreur lors du telechargement du flow !"
    Write-Host $_.Exception.Message
    exit
}

# ---- Sauvegarder dans un fichier ----
$flowContent | ConvertTo-Json -Depth 100 | Out-File $outputFile -Encoding utf8

Write-Host " Flow sauvegarde dans : $outputFile"

