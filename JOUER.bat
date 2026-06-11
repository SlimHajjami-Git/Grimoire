@echo off
rem Lance le jeu directement (sans passer par l'editeur Godot).
rem Pour tester a 2 : double-clique ce fichier DEUX FOIS.
rem Fenetre 1 -> HEBERGER  |  Fenetre 2 -> REJOINDRE 127.0.0.1
start "" "%~dp0tools\Godot_v4.4.1-stable_win64.exe" --path "%~dp0."
