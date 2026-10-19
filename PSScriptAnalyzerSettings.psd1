@{
    Severity     = @('Error', 'Warning')
    # The installer is an interactive console script: Write-Host is its output.
    ExcludeRules = @('PSAvoidUsingWriteHost')
}
