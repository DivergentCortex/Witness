# ConvertTo-WitnessRedactedText.ps1
# Credential redaction applied to every Write-Log message.
#
# Port of py/pylogger/redaction.py: the same patterns and the same replacement text, so a
# line redacted in any language logger reads identically. Shapes: GitHub tokens (classic and
# fine-grained), AWS access key ids, Slack tokens, PEM private keys (header and body), inline
# bearer headers, and credentials embedded in a URL (user:secret@host and the single-field
# token@host form).
#
# KNOWN FALSE POSITIVE, accepted deliberately: the AWS rule matches the vendor's own
# published example key.

$script:WitnessRedacted = '[REDACTED]'

$script:WitnessSecretValueRegex = [regex]::new(
    '(?:gh[pousr]_[A-Za-z0-9]{16,}' +
    '|github_pat_[A-Za-z0-9_]{20,}' +
    '|AKIA[0-9A-Z]{16}' +
    '|xox[baprs]-[A-Za-z0-9-]{10,}' +
    '|-----BEGIN[ A-Z]*PRIVATE KEY(?:-----[^-]{0,4096})?' +
    '|Bearer\s+[A-Za-z0-9._~+/-]{20,})',
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)

# The scheme is bounded (a letter and at most 31 more characters) so matching stays linear.
$script:WitnessUrlScheme = '[a-zA-Z][a-zA-Z0-9+.\-]{0,31}://'
$script:WitnessUrlCredentialRegex = [regex]::new(
    '(' + $script:WitnessUrlScheme + ')([^/\s:@]+):([^/\s@]+)@',
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
$script:WitnessUrlTokenRegex = [regex]::new(
    '(' + $script:WitnessUrlScheme + ')([^/\s:@]{20,})@',
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)

function ConvertTo-WitnessRedactedText {
    <#
    .SYNOPSIS
        Removes credential-shaped substrings from text, keeping everything else.

    .DESCRIPTION
        Each match becomes [REDACTED]; a URL keeps its scheme (and user, for the user:secret
        form). Idempotent. Same patterns and replacement text as pylogger redact().

    .PARAMETER Text
        The text to redact. An empty string is returned unchanged.

    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text
    )

    $withoutUrlCredentials = $script:WitnessUrlCredentialRegex.Replace($Text, '${1}${2}:[REDACTED]@')
    $withoutUrlTokens = $script:WitnessUrlTokenRegex.Replace($withoutUrlCredentials, '${1}[REDACTED]@')
    return $script:WitnessSecretValueRegex.Replace($withoutUrlTokens, $script:WitnessRedacted)
}
