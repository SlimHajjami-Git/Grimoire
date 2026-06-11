@echo off
rem Lance un serveur dedie headless (sans fenetre de jeu) sur le port 7777.
rem Les joueurs s'y connectent avec REJOINDRE + ton IP.
"%~dp0tools\Godot_v4.4.1-stable_win64_console.exe" --headless --path "%~dp0." -- --server
pause
