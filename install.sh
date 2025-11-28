#!/bin/bash

# --- CONFIGURAÇÕES ---
# URL DO SEU REPOSITÓRIO (Atualizada)
REPO_URL="https://github.com/robertocjunior/jukebox.git" 
INSTALL_DIR="/opt/jukebox"
APP_USER="jukebox"

# Cores para logs
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}>>> Iniciando Instalação da Jukebox Pro...${NC}"

# 1. Verificação de Root
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, rode este script como root (sudo su)"
  exit
fi

# 2. Atualizar Sistema e Instalar Dependências Básicas
echo -e "${GREEN}>>> Atualizando sistema e instalando dependências...${NC}"
apt update && apt upgrade -y

# Instala avahi-daemon para suporte a .local
apt install -y curl git ffmpeg mpv python3 python3-pip python3-venv build-essential avahi-daemon

# Habilita o Avahi
systemctl enable avahi-daemon
systemctl start avahi-daemon

# 3. Instalar Docker e Docker Compose
echo -e "${GREEN}>>> Instalando Docker...${NC}"
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
else
    echo "Docker já instalado."
fi

apt install -y docker-compose-plugin

# 4. Instalar Node.js (Versão 18 LTS)
echo -e "${GREEN}>>> Instalando Node.js 18...${NC}"
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt install -y nodejs
else
    echo "Node.js já instalado."
fi

# 5. Instalar yt-dlp (Versão mais recente via GitHub)
echo -e "${GREEN}>>> Instalando yt-dlp...${NC}"
curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
chmod a+rx /usr/local/bin/yt-dlp

# 6. Criar Usuário de Serviço
echo -e "${GREEN}>>> Configurando usuário do sistema...${NC}"
if ! id "$APP_USER" &>/dev/null; then
    useradd -m -s /bin/bash $APP_USER
    usermod -aG audio $APP_USER
    usermod -aG docker $APP_USER
    echo "Usuário $APP_USER criado."
fi

# 7. Clonar/Atualizar Repositório
echo -e "${GREEN}>>> Baixando a Jukebox...${NC}"
if [ -d "$INSTALL_DIR" ]; then
    echo "Pasta já existe. Atualizando..."
    cd $INSTALL_DIR
    git pull
else
    git clone $REPO_URL $INSTALL_DIR
fi

chown -R $APP_USER:$APP_USER $INSTALL_DIR

# 8. Instalar Dependências e Subir DB
echo -e "${GREEN}>>> Instalando dependências e subindo Banco de Dados...${NC}"
cd $INSTALL_DIR
docker compose up -d
su - $APP_USER -c "cd $INSTALL_DIR && npm install"

# 9. Configurar PM2
echo -e "${GREEN}>>> Configurando PM2...${NC}"
npm install -g pm2

# Roda o app e salva
su - $APP_USER -c "cd $INSTALL_DIR && export XDG_RUNTIME_DIR=/run/user/$(id -u $APP_USER) && pm2 start src/server.js --name jukebox"
su - $APP_USER -c "pm2 save"

# Configura startup
env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u $APP_USER --hp /home/$APP_USER

# --- EXIBIÇÃO FINAL ---
HOST_NAME=$(hostname)
IP_ADDR=$(hostname -I | awk '{print $1}')

echo -e "${GREEN}>>> INSTALAÇÃO CONCLUÍDA! <<<${NC}"
echo "---------------------------------------------------"
echo "Acesse pelo nome: http://$HOST_NAME.local:3000"
echo "Acesse pelo IP:   http://$IP_ADDR:3000"
echo "---------------------------------------------------"
echo "Usuário padrão deve ser criado no primeiro acesso."
