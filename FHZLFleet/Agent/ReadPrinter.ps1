Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$intervalMs = 1000

$desktop = [System.Windows.Automation.AutomationElement]::RootElement

$script:printer = $null
$script:infoElement = $null

function Get-MatchedValue {
    param(
        [string]$Text,
        [string]$Pattern
    )

    $match = [regex]::Match($Text, $Pattern)

    if ($match.Success) {
        return $match.Groups[1].Value.Trim()
    }

    return ""
}

function Get-PrinterState {

    try {
        if ($null -eq $script:printer) {
            $windows = $desktop.FindAll(
                [System.Windows.Automation.TreeScope]::Children,
                [System.Windows.Automation.Condition]::TrueCondition
            )

            foreach ($window in $windows) {
                try {
                    if ($window.Current.Name -match "FHZLPrinterManager") {
                        $script:printer = $window
                        break
                    }
                }
                catch {
                    continue
                }
            }
        }

        if ($null -eq $script:printer) {
            return "ERROR|WINDOW_NOT_FOUND"
        }
        else {
            if ($null -eq $script:infoElement) {
                $elements = $script:printer.FindAll(
                    [System.Windows.Automation.TreeScope]::Descendants,
                    [System.Windows.Automation.Condition]::TrueCondition
                )

                foreach ($element in $elements) {
                    try {
                        if ($element.Current.Name -match "Finished\s*time") {
                            $script:infoElement = $element
                            break
                        }
                    }
                    catch {
                        continue
                    }
                }
            }

            if ($null -eq $script:infoElement) {
                return "ERROR|TEXT_NOT_FOUND"
            }
            else {
                $text = $script:infoElement.Current.Name

                if ($text -notmatch "Finished\s*time") {
                    $script:infoElement = $null
                    return "ERROR|TEXT_NOT_FOUND"
                }
                else {
                    $kind = "FINISHED"

                    if ($text -match "Estimate(?:d)?\s+Finished\s*time") {
                        $kind = "ESTIMATE"
                    }

                    # Date and time may be on separate lines.
                    $endTime = Get-MatchedValue $text `
                        '(?im)^\s*(?:Estimate(?:d)?\s+)?Finished\s*time\s*:\s*(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})'

                    # Normalize line breaks between date and time.
                    $endTime = $endTime -replace '\s+', ' '

                    $printed = Get-MatchedValue $text `
                        '(?im)^\s*Printed\s*/\s*Total\s*:\s*(\d+)\s*/\s*\d+'

                    $total = Get-MatchedValue $text `
                        '(?im)^\s*Printed\s*/\s*Total\s*:\s*\d+\s*/\s*(\d+)'

                    $startTime = Get-MatchedValue $text `
                        '(?im)^\s*Start\s*time\s*:\s*(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})'

                    $startTime = $startTime -replace '\s+', ' '

                    $duration = Get-MatchedValue $text `
                        '(?im)^\s*Total\s*time\s*:\s*(\d+:\d{2}:\d{2})'

                    $fields = @(
                        "OK"
                        "STATE"
                        $kind
                        $endTime
                        $printed
                        $total
                        $startTime
                        $duration
                    )

                    return ($fields -join "|")
                }
            }
        }
    }
    catch {
        $script:printer = $null
        $script:infoElement = $null

        return "ERROR|READ_FAILED"
    }

}
