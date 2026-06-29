#
# DivergentCortex.Witness -- Banner Configuration
#
# This file controls the session-start banner that Initialize-Log prints to the
# console and writes to the log file at the top of every run.
#
# HOW TO CUSTOMIZE:
#   Edit this file directly, or point Initialize-Log at your own copy:
#
#       Initialize-Log -LogFilePath 'C:\Logs\run.log' -BannerConfigPath 'C:\MyConfig\banner.psd1'
#
#   You can also set a global override before importing the module:
#
#       $Global:WitnessBannerConfigPath = 'C:\MyConfig\banner.psd1'
#
# SCHEMA:
#   Enabled       - $true/$false. Set to $false to suppress the banner entirely.
#   Separator     - The line used as top/bottom border. Must be ASCII only.
#   HeaderLines   - Static lines printed after the top separator (before context fields).
#                   Use @() for none. Good for branding or a title.
#   Fields        - Ordered list of context fields to include. Each entry is a hashtable:
#                       Name  - the context key (see supported keys below)
#                       Label - the label shown in the banner (padded to align)
#                   Remove an entry to hide that field. Reorder to change layout.
#   FooterLines   - Static lines printed after context fields (before bottom separator).
#                   Use @() for none.
#
# SUPPORTED FIELD NAMES (Name key):
#   ScriptName    - the -ScriptName value passed to Initialize-Log
#   Time          - current timestamp (yyyy-MM-dd HH:mm:ss)
#   Identity      - Windows identity / domain\user
#   Context       - SYSTEM or USER, plus Admin flag
#   Platform      - OS platform string
#   EnvUser       - environment USERDOMAIN\USERNAME
#   Interactive   - interactive user flag
#   Session       - session type
#   Host          - machine hostname
#   PID           - process ID
#   LogFile       - resolved log file path
#   Version       - the -Version value passed to Initialize-Log
#

@{
    Enabled     = $true

    Separator   = '==============================================================================='

    HeaderLines = @(
        # Add static branding or title lines here. Example:
        #   'MY COMPANY -- DEPLOYMENT AUTOMATION'
        #   ''
    )

    Fields      = @(
        @{ Name = 'ScriptName'; Label = 'SCRIPT START' }
        @{ Name = 'Time'; Label = 'TIME' }
        @{ Name = 'Identity'; Label = 'IDENTITY' }
        @{ Name = 'Context'; Label = 'CONTEXT' }
        @{ Name = 'Platform'; Label = 'PLATFORM' }
        @{ Name = 'EnvUser'; Label = 'ENV USER' }
        @{ Name = 'Interactive'; Label = 'INTERACTIVE' }
        @{ Name = 'Session'; Label = 'SESSION' }
        @{ Name = 'Host'; Label = 'HOST' }
        @{ Name = 'PID'; Label = 'PID' }
        @{ Name = 'LogFile'; Label = 'LOG' }
        @{ Name = 'Version'; Label = 'VERSION' }
    )

    FooterLines = @(
        # Add static footer lines here. Example:
        #   'All activity is logged and monitored.'
    )
}
