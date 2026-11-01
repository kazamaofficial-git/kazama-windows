# ============================================================
# Kazama Debloat Catalog — what Storage Booster `-Mode max` may remove
# Developer  : @kazamaofficial-git
# ============================================================
# Edit freely. Each entry is only touched when it is actually present, so one
# catalog works for windows-latest, windows-2025 and windows-2022 (version folders
# such as R-4.3.x or "Visual Studio\2022" are matched with wildcards).
#
#   Id       short name — use it in -Keep / the `keep` input to protect an entry
#   Name     human readable name for logs
#   Display  Add/Remove Programs names to uninstall (wildcards allowed)
#   Services Windows services to stop first (wildcards allowed)
#   Folders  folders removed afterwards (wildcards allowed)
#   OnlyOn   optional: restrict to 'win2022' and/or 'win2025'
#   Special  'edge' = uses Edge's own uninstaller and installs Chrome first if missing
#
# Chrome is never in this list on purpose.
@{
    Apps = @(
        @{ Id = 'edge'; Name = 'Microsoft Edge'; Special = 'edge'
           Display = @('Microsoft Edge')            # exact name: WebView2 Runtime is kept
           Folders = @('C:\Program Files (x86)\Microsoft\Edge\Application', 'C:\Program Files (x86)\Microsoft\EdgeCore') }

        @{ Id = 'firefox'; Name = 'Mozilla Firefox'
           Display = @('Mozilla Firefox*', 'Mozilla Maintenance Service')
           Folders = @('C:\Program Files\Mozilla Firefox', 'C:\Program Files (x86)\Mozilla Maintenance Service') }

        @{ Id = 'unity'; Name = 'Unity'
           Display = @('Unity*')
           Folders = @('C:\Program Files\Unity*', 'C:\Program Files\Unity Hub') }

        @{ Id = 'r'; Name = 'R (R-4.x) and Rtools'
           Display = @('R for Windows*', 'Rtools*')
           Folders = @('C:\Program Files\R', 'C:\rtools*') }

        @{ Id = 'haskell'; Name = 'Haskell (GHC, Cabal, ghcup)'
           Display = @('Haskell*', 'GHC*')
           Folders = @('C:\ghcup', 'C:\cabal', 'C:\Users\*\AppData\Local\ghcup', 'C:\Users\*\AppData\Roaming\cabal', 'C:\Users\*\AppData\Local\cabal') }

        @{ Id = 'android'; Name = 'Android SDK / NDK'
           Folders = @('C:\Android', 'C:\Program Files (x86)\Android', 'C:\Users\*\.android') }

        @{ Id = 'julia'; Name = 'Julia'
           Display = @('Julia*')
           Folders = @('C:\Julia*', 'C:\Users\*\AppData\Local\Programs\Julia*') }

        @{ Id = 'miniconda'; Name = 'Miniconda'
           Display = @('Miniconda*', 'Anaconda*')
           Folders = @('C:\Miniconda*', 'C:\Users\*\miniconda3') }

        @{ Id = 'rust'; Name = 'Rust (cargo, rustup)'
           Folders = @('C:\Users\*\.cargo', 'C:\Users\*\.rustup', 'C:\Rust*') }

        @{ Id = 'msys2'; Name = 'MSYS2 / MinGW'
           Folders = @('C:\msys64', 'C:\mingw*') }

        @{ Id = 'mysql'; Name = 'MySQL'
           Services = @('MySQL*')
           Folders = @('C:\mysql*', 'C:\Program Files\MySQL') }

        @{ Id = 'postgresql'; Name = 'PostgreSQL'
           Services = @('postgresql*')
           Folders = @('C:\Program Files\PostgreSQL') }

        @{ Id = 'mongodb'; Name = 'MongoDB'
           Services = @('MongoDB*')
           Folders = @('C:\Program Files\MongoDB') }

        @{ Id = 'cosmos'; Name = 'Azure Cosmos DB Emulator'
           Display = @('Azure Cosmos DB Emulator*')
           Folders = @('C:\Program Files\Azure Cosmos DB Emulator') }

        # Largest item on GitHub runners (tens of GB). Protect it with: keep = chrome,visualstudio
        @{ Id = 'visualstudio'; Name = 'Visual Studio (IDE + build tools)'
           Folders = @('C:\Program Files\Microsoft Visual Studio', 'C:\Program Files (x86)\Microsoft Visual Studio') }
    )
}
