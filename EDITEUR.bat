@echo off
rem Ouvre le projet dans l'editeur Godot (pour modifier le jeu).
start "" "%~dp0tools\Godot_v4.4.1-stable_win64.exe" --path "%~dp0." --editor
