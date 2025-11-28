#!/bin/bash

# --- CONFIGURAÇÕES ---
INSTALL_DIR="/opt/jukebox"
APP_USER="jukebox"

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${RED}!!! ATENÇÃO !!!${NC}"
echo "Este script irá remover completamente a Jukebox Pro e todos os seus dados."
echo "Isso inclui o Banco de Dados (MongoDB) e o histórico de músicas."
echo -e "${YELLOW}Deseja continuar? (y/n)${NC}"
read -r response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
    echo "Iniciando desinstalação..."
else
    echo "Cancelado."
    exit 1
fi

# 1. Verificação de Root
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, rode este script como root (sudo ./uninstall.sh)"
  exit
fi

# 2. Parar e Remover PM2 (Gerenciador de Processos)
echo -e "${YELLOW}>>> Removendo processo e startup do PM2...${NC}"
if id "$APP_USER" &>/dev/null; then
    # Remove o script de inicialização do sistema
    pm2 unstartup systemd -u $APP_USER >/dev/null 2>&1
    
    # Para e deleta o processo
    su - $APP_USER -c "pm2 delete jukebox" >/dev/null 2>&1
    su - $APP_USER -c "pm2 save" >/dev/null 2>&1
    su - $APP_USER -c "pm2 kill" >/dev/null 2>&1
    
    # Opcional: Remover PM2 globalmente se não usado por outros apps
    # npm uninstall -g pm2
else
    echo "Usuário $APP_USER não encontrado, pulando etapa do PM2."
fi

# 3. Remover Container e Volume do Docker
echo -e "${YELLOW}>>> Removendo Banco de Dados e Containers...${NC}"
if [ -d "$INSTALL_DIR" ]; then
    cd $INSTALL_DIR
    if command -v docker &> /dev/null; then
        # Derruba containers e apaga volumes (-v)
        docker compose down -v >/dev/null 2>&1
    fi
fi

# Limpeza extra garantida do docker
if command -v docker &> /dev/null; then
    docker rm -f jukebox-db >/dev/null 2>&1
    docker volume rm jukebox-pro_mongo-data >/dev/null 2>&1
fi

# 4. Remover Diretórios e Arquivos
echo -e "${YELLOW}>>> Apagando arquivos da aplicação...${NC}"
rm -rf $INSTALL_DIR

# 5. Remover Binário yt-dlp
echo -e "${YELLOW}>>> Removendo yt-dlp...${NC}"
rm -f /usr/local/bin/yt-dlp

# 6. Remover Usuário do Sistema
echo -e "${YELLOW}>>> Removendo usuário $APP_USER...${NC}"
if id "$APP_USER" &>/dev/null; then
    # -r remove a pasta home (/home/jukebox)
    # -f força a remoção mesmo se tiver processos presos
    userdel -r -f $APP_USER
    echo "Usuário removido."
else
    echo "Usuário já não existe."
fi

# 7. (Opcional) Limpar dependências não utilizadas
# Nota: Não removemos Node.js, Docker ou FFmpeg pois podem ser usados por outros apps do sistema.
# Se quiser remover TUDO mesmo, descomente as linhas abaixo:
# apt remove -y nodejs npm ffmpeg mpv avahi-daemon
# apt autoremove -y

echo -e "${GREEN}>>> DESINSTALAÇÃO CONCLUÍDA COM SUCESSO! <<<${NC}"
echo "O sistema está limpo da Jukebox Pro."
