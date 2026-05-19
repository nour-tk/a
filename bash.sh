yay -Rns caelestia-shell caelestia-cli --noconfirm
rm -rf ~/.config/caelestia ~/.local/share/caelestia

git clone https://github.com/caelestia-dots/caelestia.git ~/.local/share/caelestia
yay -S --needed --noconfirm caelestia-shell caelestia-cli
fish ~/.local/share/caelestia/install.fish
