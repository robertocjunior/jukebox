#!/bin/bash

# --- CONFIGURAÇÕES ---
# COLOQUE O LINK DO SEU REPOSITÓRIO AQUI:
REPO_URL="https://github.com/robertocjunior/jukebox-pro.git" 
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

# ADICIONADO: avahi-daemon para suporte a .local
apt install -y curl git ffmpeg mpv python3 python3-pip python3-venv build-essential avahi-daemon

# Habilita o Avahi para iniciar no boot
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

# Instalar Docker Compose (Plugin V2)
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

# 6. Criar Usuário de Serviço (Segurança)
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

# Ajustar permissões para o usuário da jukebox
chown -R $APP_USER:$APP_USER $INSTALL_DIR

# 8. Instalar Dependências do Projeto e Subir DB
echo -e "${GREEN}>>> Instalando dependências NPM e subindo Banco de Dados...${NC}"
cd $INSTALL_DIR

# Sobe o MongoDB via Docker
docker compose up -d

# Instala pacotes do Node como o usuário jukebox (não root)
su - $APP_USER -c "cd $INSTALL_DIR && npm install"

# 9. Configurar PM2 (Gerenciador de Processos)
echo -e "${GREEN}>>> Configurando PM2 para rodar 24/7...${NC}"

# Instala PM2 globalmente
npm install -g pm2

# Roda o app como o usuário jukebox e salva
su - $APP_USER -c "cd $INSTALL_DIR && export XDG_RUNTIME_DIR=/run/user/$(id -u $APP_USER) && pm2 start src/server.js --name jukebox"
su - $APP_USER -c "pm2 save"

# Gera e executa o script de startup do sistema
env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u $APP_USER --hp /home/$APP_USER

echo -e "${GREEN}>>> INSTALAÇÃO CONCLUÍDA! <<<${NC}"
echo "Acesse em: http://$(hostname).local:3000"
echo "Ou pelo IP: http://$(hostname -I | awk '{print $1}'):3000"
