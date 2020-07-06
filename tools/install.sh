#!/bin/sh

set -e

# Default settings
DOTFILES=${DOTFILES:-~/.dotfiles}
repo=${repo:-lannuttia/dotfiles}
remote=${remote:-https://github.com/${repo}.git}
branch=${branch:-master}

chsh=${chsh:-true}
ssh_keygen=${ssh_keygen:-true}
gpg_keygen=${gpg_keygen:-true}
git_config=${git_config:-true}
install_ranger=${install_ranger:-true}

error() {
	echo ${RED}"Error: $@"${RESET} >&2
}

if [ -f /etc/os-release ] || [ -f /usr/lib/os-release ] || [ -f /etc/openwrt_release ] || [ -f /etc/lsb_release ]; then
   for file in /etc/os-release /usr/lib/os-release /etc/openwrt_release /etc/lsb_release; do
     echo "checkingi if $file exists"
     [ -f "$file" ] && echo "Sourcing $file" && . "$file" && break
   done
else
  error 'Failed to sniff environment'
  exit 1
fi

if [ $ID_LIKE ]; then
  os=$ID_LIKE
else
  os=$ID
fi

command_exists() {
	command -v "$@" >/dev/null 2>&1
}

run_as_root() {
  if [ "$EUID" = 0 ]; then
    eval "$*"
  elif command_exists sudo; then
    sudo -v
    if [ $? -eq 0 ]; then
      eval "sudo sh -c '$*'"
    else
      su -c "$*"
    fi
  else
    su -c "$*"
  fi
}

setup_color() {
	# Only use colors if connected to a terminal
	if [ -t 1 ]; then
		RED=$(printf '\033[31m')
		GREEN=$(printf '\033[32m')
		YELLOW=$(printf '\033[33m')
		BLUE=$(printf '\033[34m')
		BOLD=$(printf '\033[1m')
		RESET=$(printf '\033[m')
	else
		RED=""
		GREEN=""
		YELLOW=""
		BLUE=""
		BOLD=""
		RESET=""
	fi
}

clone_dotfiles() {
  echo "${BLUE}Cloning Anthony Lannutti's Dotfiles...${RESET}"

  command_exists git || {
    error "git is not installed"
    exit 1
  }

  if [ "$OSTYPE" = cygwin ] && git --version | grep -q msysgit; then
		error "Windows/MSYS Git is not supported on Cygwin"
		error "Make sure the Cygwin git package is installed and is first on the \$PATH"
		exit 1
	fi

  if [ ! -d $DOTFILES ]; then
    git clone -c core.eol=lf \
      -c fsck.zeroPaddedFilemode=ignore \
      -c fetch.fsck.zeroPaddedFilemode=ignore \
      -c receive.fsck.zeroPaddedFilemode=ignore \
      --branch "$branch" "$remote" "$DOTFILES" || {
      error "git clone of Anthony Lannutti's Dotfiles repo failed"
      exit 1
    }
  fi

  echo
}

setup_shell() {
  if [ "$chsh" = false ]; then
    return
  fi

  if ! command_exists chsh; then
    cat <<-EOF
			I can't change your shell automatically because this system does not have chsh.
			${BLUE}If you want a different shell, you will have to manually change it.${RESET}
		EOF
  fi

  if [ "$chsh" = true ]; then
    echo "${YELLOW}Select one of these shells to be your default shell${RESET}"
    grep -v '^#' /etc/shells
    read user_shell;
    chsh --shell $user_shell $USER
  fi
}

setup_gitconfig() {
  if [ "$git_config" = true ]; then
    echo -n 'What is the email address you want to use for git: '
    read git_user_email
    git config --global user.email "$git_user_email"
    
    echo -n 'What is the name you want to use for git: '
    read git_user_name
    git config --global user.name "$git_user_name"
  
    git config --global core.autocrlf input
  fi
}

setup_ssh() {
  if [ "$ssh_keygen" = true ] && [ ! -f $HOME/.ssh/id_rsa ] && [ ! -f $HOME/.ssh/id_rsa.pub ]; then
    echo -n 'What is the email address for you SSH key: '
    read ssh_email
    ssh-keygen -t rsa -f $HOME/.ssh/id_rsa -b 4096 -C $ssh_email
  fi
}

setup_gpg() {
  echo $gpg_keygen
  if [ "$gpg_keygen" = true ]; then
    if command_exists gpg2; then
      gpg2 --full-generate-key
    elif command_exists gpg; then
      gpg --full-generate-key
    else
      error "Could not find the gpg executible"
    fi
  fi
}

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo
  echo "OPTIONS:"
  echo -e "\t--help\t\t\tDisplay this help menu"
  echo -e "\t--no-chsh\t\tSkip running chsh for user [DEFAULT=$([ "$chsh" = true ] && echo "false" || echo "true")]"
  echo -e "\t--no-ssh-keygen\t\tSkip automated SSH key generation"
  echo -e "\t--no-gpg-keygen\t\tSkip interactive GPG key generation"
  echo -e "\t--no-git-config\t\tSkip interactive Git configuration"
  echo -e "\t--no-ranger\t\tDo not install the Ranger file explorer"
  echo -e "\t--no-interactive\t\tSkip all interactive steps"
}

update() {
  case $os in
    debian|ubuntu)
      run_as_root apt update
    ;;
    alpine)
      run_as_root apk update
    ;;
    arch|artix)
      run_as_root pacman -Sy
    ;;
    *)
      error "Unsupported Distribution: $os"
      exit 1
    ;;
  esac
}

add_repositories() {
  case $ID in
      kali)
        echo 'No additional repositorys will be added for Kali'
        run_as_root apt install --no-install-recommends -y ca-certificates curl apt-transport-https gnupg
      ;;
      ubuntu|elementary)
        arch=$(dpkg --print-architecture)
        echo 'Installing minimal packages to add Azure CLI repository'
        run_as_root apt install --no-install-recommends -y ca-certificates curl apt-transport-https gnupg
        echo 'Adding Microsoft signing key'
        curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | run_as_root tee /etc/apt/trusted.gpg.d/microsoft.asc.gpg > /dev/null
        echo 'Adding Microsoft Azure CLI repository'
        echo "deb [arch=${arch}] https://packages.microsoft.com/repos/azure-cli/ ${UBUNTU_CODENAME:-$VERSION_CODENAME} main" | run_as_root tee /etc/apt/sources.list.d/azure-cli.list
      ;;
      debian)
        arch=$(dpkg --print-architecture)
        echo 'Installing minimal packages to add Azure CLI repository'
        run_as_root apt install --no-install-recommends -y ca-certificates curl apt-transport-https gnupg
        echo 'Adding Microsoft signing key'
        curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | run_as_root tee /etc/apt/trusted.gpg.d/microsoft.asc.gpg > /dev/null
        echo 'Adding Microsoft Azure CLI repository'
        echo "deb [arch=${arch}] https://packages.microsoft.com/repos/azure-cli/ ${VERSION_CODENAME} main" | run_as_root tee /etc/apt/sources.list.d/azure-cli.list
      ;;
      alpine)
        echo 'No additional repositorys will be added for Alpine'
        run_as_root apk add ca-certificates curl gnupg
      ;;
      arch|artix)
      ;;
      *)
          error "Unsupported OS: $NAME"
          exit 1
      ;;
  esac
}

packages() {
  case $ID in
    kali)
      case $VERSION_ID in
        *)
          echo -n 'git gnupg python3 python3-pip openssh-client dnsutils vim neofetch zsh dvtm azure-cli'
          if [ "$install_ranger" = true ]; then
            echo -n ' ranger'
          fi
        ;;
      esac
    ;;
    ubuntu|elementary)
      case $VERSION_ID in
        18.04|5.*)
          echo -n 'git gnupg python3 python3-pip openssh-client dnsutils vim neofetch zsh dvtm azure-cli'
          if [ "$install_ranger" = true ]; then
            echo -n ' ranger'
          fi
        ;;
        20.04)
          echo -n 'git gnupg python3 python3-pip openssh-client dnsutils vim neofetch zsh dvtm azure-cli'
          if [ "$install_ranger" = true ]; then
            echo -n ' ranger'
          fi
        ;;
        *)
          error "Unsupported version of $NAME: $VERSION_ID"
          exit 1;
        ;;
      esac
    ;;
    debian)
      case $VERSION_ID in
        10)
          echo -n 'git gnupg python3 python3-pip openssh-client dnsutils vim neofetch zsh dvtm azure-cli'
          if [ "$install_ranger" = true ]; then
            echo -n ' ranger'
          fi
        ;;
        9)
          echo -n 'git gnupg python3 python3-pip openssh-client dnsutils vim neofetch zsh dvtm azure-cli'
          if [ "$install_ranger" = true ]; then
            echo -n ' ranger'
          fi
        ;;
        *)
          error "Unsupported version of $NAME: $VERSION_ID"
        ;;
      esac
    ;;
    alpine)
      case $VERSION_ID in
        3\.*)
          echo -n 'git gnupg python3 py3-pip openssh-client bind-tools vim neofetch zsh dvtm'
          if [ "$install_ranger" = true ]; then
            echo -n ' ranger'
          fi
	      ;;
        *)
          error "Unsupported version of $NAME: $VERSION_ID"
        ;;
      esac
    ;;
    arch)
      echo -n 'git gnupg python python-pip openssh bind-tools vim neofetch zsh dvtm'
      if [ "$install_ranger" = true ]; then
        echo -n ' ranger'
      fi
    ;;
    artix)
      # It doesn't appear that dvtm is in the base Artix repos...
      echo -n 'git gnupg openssh bind-tools vim neofetch zsh'
      # Ranger doesn't appear to be there either
    ;;
    *)
      error "Unsupported OS: $NAME"
      exit 1
    ;;
  esac
}

install() {
  case $os in
    debian|ubuntu)
      run_as_root apt install -y $(packages)
    ;;
    arch|artix)
      run_as_root pacman -S --noconfirm $(packages)
    ;;
    alpine)
      run_as_root apk add $(packages)
    ;;
    *)
      error "Unsupported OS: $NAME"
      exit 1
    ;;
  esac
  if [ ! -d $HOME/.oh-my-zsh ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  fi
  if command_exists az; then
    az extension add --name azure-devops --name codespaces
  fi
  if command_exists pip3; then
    pip3 install yq
  fi
}

link_dotfiles() {
  for file in .vimrc .zshenv .zshrc; do
    ln -sf $DOTFILES/$file $HOME/$file
  done
}

main() {
  if [ ! -t 0 ]; then
    chsh=false
    ssh_keygen=false
    gpg_keygen=false
    git_config=false
  fi

  # Transform long options to short options
  while [ $# -gt 0 ]; do
    case $1 in
      --help) usage; exit 0 ;;
      --no-chsh) chsh=false ;;
      --no-ssh-keygen) ssh_keygen=false ;;
      --no-gpg-keygen) gpg_keygen=false ;;
      --no-git-config) git_config=false ;;
      --no-ranger) install_ranger=false ;;
      --no-interactive) chsh=false; ssh_keygen=false; gpg_keygen=false; git_config=false ;;
      *) usage >&2; exit 1 ;;
    esac
    shift
  done

  setup_color

  update
  add_repositories
  update
  install
  setup_ssh
  setup_gpg
  setup_shell
  setup_gitconfig
  clone_dotfiles
  link_dotfiles

  printf "$GREEN"
	cat <<-'EOF'
    ___        _   _                         _                             _   _   _ _      ______      _    __ _ _           
   / _ \      | | | |                       | |                           | | | | (_| )     |  _  \    | |  / _(_) |          
  / /_\ \_ __ | |_| |__   ___  _ __  _   _  | |     __ _ _ __  _ __  _   _| |_| |_ _|/ ___  | | | |___ | |_| |_ _| | ___  ___ 
  |  _  | '_ \| __| '_ \ / _ \| '_ \| | | | | |    / _` | '_ \| '_ \| | | | __| __| | / __| | | | / _ \| __|  _| | |/ _ \/ __|
  | | | | | | | |_| | | | (_) | | | | |_| | | |___| (_| | | | | | | | |_| | |_| |_| | \__ \ | |/ / (_) | |_| | | | |  __/\__ \
  \_| |_/_| |_|\__|_| |_|\___/|_| |_|\__, | \_____/\__,_|_| |_|_| |_|\__,_|\__|\__|_| |___/ |___/ \___/ \__|_| |_|_|\___||___/
                                      __/ |                                                                                   
                                     |___/                 ....are now installed!                                              
	EOF
	printf "$RESET"
}

main "$@"
