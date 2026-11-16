$ErrorActionPreference = "Stop"

$secureToken = Read-Host "Incolla il token del bot Telegram" -AsSecureString
$credential = [System.Management.Automation.PSCredential]::new(
  "telegram-bot",
  $secureToken
)
$token = $credential.GetNetworkCredential().Password

try {
  $response = Invoke-RestMethod `
    -Method Get `
    -Uri "https://api.telegram.org/bot$token/getUpdates"

  $messages = @(
    $response.result |
      Where-Object { $null -ne $_.message } |
      ForEach-Object { $_.message }
  )

  if ($messages.Count -eq 0) {
    Write-Host "Nessun messaggio trovato. Scrivi prima /start al bot e riprova."
    exit 1
  }

  $latest = $messages[-1]
  Write-Host "Telegram user_id: $($latest.from.id)"
  Write-Host "Telegram chat_id: $($latest.chat.id)"
} catch {
  Write-Error "Non è stato possibile leggere gli aggiornamenti Telegram. Controlla token e connessione."
  exit 1
} finally {
  $token = $null
  $credential = $null
  $secureToken = $null
}
