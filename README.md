# 🎵 Jukebox Pro

Uma Jukebox colaborativa self-hosted, moderna e robusta. Permite que múltiplos usuários adicionem músicas de uma fila compartilhada, controlada por um administrador, com reprodução de áudio de alta qualidade diretamente no servidor (Host).

![Status](https://img.shields.io/badge/status-active-success.svg)
![Node](https://img.shields.io/badge/node-v18+-green.svg)
![Docker](https://img.shields.io/badge/docker-mongo-blue.svg)

## ✨ Funcionalidades

-   **Reprodução de Áudio Local:** Utiliza `mpv` e `yt-dlp` para tocar áudio de alta qualidade diretamente na saída de som do servidor.
-   **Busca Integrada:** Pesquise vídeos do YouTube diretamente na interface com autocomplete e miniaturas.
-   **Fila Colaborativa:** Usuários adicionam músicas; o sistema gerencia a fila automaticamente.
-   **Sistema de Usuários (RBAC):**
    -   **Admin:** Pode gerenciar o player e criar novos usuários.
    -   **User:** Pode adicionar músicas à fila.
-   **Histórico de Reprodução:** Veja o que já tocou e adicione novamente à fila com um clique.
-   **Persistência:** Fila, histórico e volume são salvos no banco de dados (MongoDB).
-   **Interface Responsiva:** Design "Matte Black" moderno que funciona em Desktop e Mobile.

---

## 🚀 Instalação

O projeto foi desenhado para rodar em **Linux (Debian/Ubuntu)**. Existem duas formas de instalar:

### Opção 1: Instalação Automática (Recomendada)

Utilize o script de instalação incluído para configurar todo o ambiente (Dependências, Docker, Banco de Dados, Usuário de Serviço e Inicialização automática).

1.  Baixe o script de instalação:
    ```bash
    wget https://raw.githubusercontent.com/robertocjunior/jukebox/main/install.sh
    ```

2.  Dê permissão de execução:
    ```bash
    chmod +x install.sh
    ```

3.  Execute como **root**:
    ```bash
    sudo ./install.sh
    ```

O script irá:
* Instalar Node.js, Docker, FFmpeg, MPV e Python.
* Baixar e configurar o `yt-dlp` mais recente.
* Criar um usuário de sistema `jukebox` para segurança.
* Configurar o PM2 para rodar a aplicação 24/7 (iniciando no boot).

---

### Opção 2: Instalação Manual

Se preferir configurar manualmente:

#### 1. Pré-requisitos
* Node.js 18+
* Docker & Docker Compose
* FFmpeg & MPV
* Python 3 & PIP

#### 2. Instalar yt-dlp
```bash
sudo curl -L [https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp](https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp) -o /usr/local/bin/yt-dlp
sudo chmod a+rx /usr/local/bin/yt-dlp
````

#### 3\. Configurar o Projeto

```bash
# Clone o repositório
git clone [https://github.com/seu-usuario/jukebox-pro.git](https://github.com/seu-usuario/jukebox-pro.git)
cd jukebox-pro

# Suba o Banco de Dados
docker compose up -d

# Instale as dependências do Node
npm install
```

#### 4\. Rodar

Para rodar em background e gerenciar o processo:

```bash
npm install -g pm2
pm2 start src/server.js --name "jukebox"
pm2 save
```

-----

## ⚙️ Configuração Inicial

1.  Acesse a interface web através do IP do servidor na porta 3000:
    `http://SEU_IP_DO_SERVIDOR:3000`

2.  **Primeiro Acesso:**
    O sistema detectará que não existem usuários e pedirá para você criar o **Administrador**.

      * Preencha Nome, Sobrenome, Usuário e Senha.

3.  **Adicionar Usuários:**
    Após logar como Admin, clique no botão **"+"** no canto superior direito (no cabeçalho do usuário) para criar contas para seus amigos/familiares.

-----

## 🛠️ Tecnologias Utilizadas

  * **Backend:** Node.js, Express, Socket.io
  * **Database:** MongoDB (via Docker)
  * **Core Media:** MPV, YT-DLP, FFmpeg
  * **Frontend:** HTML5, CSS3 (Flexbox/Grid), JavaScript (Vanilla)
  * **Gerenciamento de Processos:** PM2

-----

## 📝 Troubleshooting

**O player mostra que está tocando, mas não sai som:**
Isso geralmente é problema de permissão do usuário linux ou variável de ambiente. Se estiver rodando via PM2, tente reiniciar forçando o runtime directory:

```bash
pm2 delete jukebox
export XDG_RUNTIME_DIR=/run/user/$(id -u)
pm2 start src/server.js --name "jukebox"
```

**A busca não retorna resultados:**
O YouTube atualiza frequentemente suas páginas. Atualize o `yt-dlp`:

```bash
sudo yt-dlp -U
```
----
## 🔊 Solução de Problemas de Áudio (Debian/Linux)

Se o player estiver rodando mas **não sair som** na caixa conectada ao servidor, é provável que o volume do sistema esteja mutado ou baixo por padrão.

Siga estes passos no terminal do servidor:

1.  **Abra o mixer de áudio:**
    ```bash
    alsamixer
    ```

2.  **Selecione a Placa de Som:**
    * Aperte **`F6`** e selecione sua placa de som real (geralmente *HDA Intel* ou *Realtek*). Evite a opção "Default".

3.  **Verifique se está Mutado:**
    * Olhe para as barras verticais (Master, PCM, Speaker, Headphone).
    * Se houver as letras **`MM`** na base da barra, o canal está **Mudo**.
    * Navegue com as setas `←` / `→` até o canal e aperte a tecla **`M`** para desmutar (deve mudar para **`00`** ou ficar verde).

4.  **Aumente o Volume:**
    * Use a seta para **Cima `↑`** para aumentar o volume (recomendado deixar acima de 80%).

5.  **Dica Importante (Auto-Mute):**
    * Se houver uma barra chamada **Auto-Mute Mode** na direita, mude para **Disabled** usando as setas para cima/baixo. Isso evita que o som corte se o sistema achar que não tem fone conectado.

6.  **Salve as configurações:**
    * Aperte `Esc` para sair do alsamixer.
    * Rode o comando abaixo para gravar a configuração e não perder ao reiniciar:
    ```bash
    sudo alsactl store
    ```
