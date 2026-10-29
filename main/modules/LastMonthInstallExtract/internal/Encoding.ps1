$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 での実行を前提に、PowerShell 7 専用構文は使用しない。

function Test-LastMonthInstallExtractBytesPrefix {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes,
        [Parameter(Mandatory)][byte[]]$Prefix
    )

    if ($Bytes.Length -lt $Prefix.Length) { return $false }

    for ($i = 0; $i -lt $Prefix.Length; $i++) {
        if ($Bytes[$i] -ne $Prefix[$i]) { return $false }
    }

    return $true
}

function Test-LastMonthInstallExtractByteArrayEqual {
    param(
        [Parameter(Mandatory)][byte[]]$A,
        [Parameter(Mandatory)][byte[]]$B
    )

    if ($A.Length -ne $B.Length) { return $false }

    for ($i = 0; $i -lt $A.Length; $i++) {
        if ($A[$i] -ne $B[$i]) { return $false }
    }

    return $true
}

function Register-LastMonthInstallExtractCodePagesEncodingProviderSafely {
    try {
        $providerType = [type]::GetType('System.Text.CodePagesEncodingProvider, System.Text.Encoding.CodePages')
        if ($providerType) {
            $provider = $providerType.GetProperty('Instance').GetValue($null)
            [System.Text.Encoding]::RegisterProvider($provider)
        }
    }
    catch {
        # Windows PowerShell 5.1 では不要な場合があるため無視する。
    }
}

function Get-LastMonthInstallExtractEncodingGuessFromBytes {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)

    if (Test-LastMonthInstallExtractBytesPrefix -Bytes $Bytes -Prefix ([byte[]]@(0xEF, 0xBB, 0xBF))) { return 'UTF-8 BOM付き' }
    if (Test-LastMonthInstallExtractBytesPrefix -Bytes $Bytes -Prefix ([byte[]]@(0xFF, 0xFE, 0x00, 0x00))) { return 'UTF-32 LE BOM付き' }
    if (Test-LastMonthInstallExtractBytesPrefix -Bytes $Bytes -Prefix ([byte[]]@(0x00, 0x00, 0xFE, 0xFF))) { return 'UTF-32 BE BOM付き' }
    if (Test-LastMonthInstallExtractBytesPrefix -Bytes $Bytes -Prefix ([byte[]]@(0xFF, 0xFE))) { return 'UTF-16 LE BOM付き' }
    if (Test-LastMonthInstallExtractBytesPrefix -Bytes $Bytes -Prefix ([byte[]]@(0xFE, 0xFF))) { return 'UTF-16 BE BOM付き' }

    try {
        $utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
        [void]$utf8Strict.GetString($Bytes)
        return 'UTF-8 BOMなし'
    }
    catch {}

    Register-LastMonthInstallExtractCodePagesEncodingProviderSafely

    try {
        $cp932 = [System.Text.Encoding]::GetEncoding(
            932,
            [System.Text.EncoderFallback]::ExceptionFallback,
            [System.Text.DecoderFallback]::ExceptionFallback
        )
        $decoded = $cp932.GetString($Bytes)
        $roundTripBytes = $cp932.GetBytes($decoded)
        if (Test-LastMonthInstallExtractByteArrayEqual -A $Bytes -B $roundTripBytes) {
            return 'Shift_JIS / CP932 推定'
        }
    }
    catch {}

    return '不明'
}

function New-LastMonthInstallExtractDecodedTextResult {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$EncodingName
    )

    return [pscustomobject]@{
        Text = $Text
        EncodingName = $EncodingName
    }
}

function ConvertFrom-LastMonthInstallExtractSupportedBytes {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)

    if ($Bytes.Length -eq 0) { throw '空ファイルです。' }

    if (Test-LastMonthInstallExtractBytesPrefix -Bytes $Bytes -Prefix ([byte[]]@(0xFF, 0xFE, 0x00, 0x00))) {
        $encoding = New-Object System.Text.UTF32Encoding($false, $true, $true)
        return New-LastMonthInstallExtractDecodedTextResult -Text ($encoding.GetString($Bytes, 4, $Bytes.Length - 4)) -EncodingName 'UTF-32 LE BOM付き'
    }

    if (Test-LastMonthInstallExtractBytesPrefix -Bytes $Bytes -Prefix ([byte[]]@(0x00, 0x00, 0xFE, 0xFF))) {
        $encoding = New-Object System.Text.UTF32Encoding($true, $true, $true)
        return New-LastMonthInstallExtractDecodedTextResult -Text ($encoding.GetString($Bytes, 4, $Bytes.Length - 4)) -EncodingName 'UTF-32 BE BOM付き'
    }

    if (Test-LastMonthInstallExtractBytesPrefix -Bytes $Bytes -Prefix ([byte[]]@(0xEF, 0xBB, 0xBF))) {
        $encoding = New-Object System.Text.UTF8Encoding($false, $true)
        return New-LastMonthInstallExtractDecodedTextResult -Text ($encoding.GetString($Bytes, 3, $Bytes.Length - 3)) -EncodingName 'UTF-8 BOM付き'
    }

    if (Test-LastMonthInstallExtractBytesPrefix -Bytes $Bytes -Prefix ([byte[]]@(0xFF, 0xFE))) {
        $encoding = New-Object System.Text.UnicodeEncoding($false, $true, $true)
        return New-LastMonthInstallExtractDecodedTextResult -Text ($encoding.GetString($Bytes, 2, $Bytes.Length - 2)) -EncodingName 'UTF-16 LE BOM付き'
    }

    if (Test-LastMonthInstallExtractBytesPrefix -Bytes $Bytes -Prefix ([byte[]]@(0xFE, 0xFF))) {
        $encoding = New-Object System.Text.UnicodeEncoding($true, $true, $true)
        return New-LastMonthInstallExtractDecodedTextResult -Text ($encoding.GetString($Bytes, 2, $Bytes.Length - 2)) -EncodingName 'UTF-16 BE BOM付き'
    }

    try {
        $encoding = New-Object System.Text.UTF8Encoding($false, $true)
        return New-LastMonthInstallExtractDecodedTextResult -Text ($encoding.GetString($Bytes)) -EncodingName 'UTF-8 BOMなし'
    }
    catch {
        $guess = Get-LastMonthInstallExtractEncodingGuessFromBytes -Bytes $Bytes
        throw "対応文字コードとして読めません。対応: UTF-8、UTF-16 BOM付き、UTF-32 BOM付き。推定文字コード: $guess / 詳細: $($_.Exception.Message)"
    }
}
