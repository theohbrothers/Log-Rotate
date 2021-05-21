function Get-Exception-Message ($ErrorRecord) {
    # Recurses to get the innermost exception message
    function Get-InnerExceptionMessage ($Exception) {
        if ($Exception.InnerException) {
            Get-InnerExceptionMessage $Exception.InnerException
        }else {
            $Exception.Message
        }
    }
    $Message = Get-InnerExceptionMessage $ErrorRecord.Exception
    if ($WhatIf) {
        $Message = $Message  + "`nStacktrace:`n" + $ErrorRecord.Exception.ErrorRecord.ScriptStackTrace
    }
    $Message
}
