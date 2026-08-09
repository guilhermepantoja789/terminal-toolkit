# dotfiles

Setup CLI portável para **Linux (Debian)** e **macOS** — yazi, micro, Tabby (macOS) / kitty (Linux), glow, shell customizado e scripts de produtividade.

## Quick start

```bash
git clone https://github.com/guilhermepantoja/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

Preview sem alterar o sistema:

```bash
./install.sh --dry-run
```

Atualizar configs após `git pull`:

```bash
cd ~/dotfiles && git pull && ./install.sh --configs-only
```

## O que instala

| Ferramenta | Linux (apt/cargo) | macOS (Homebrew) |
|-----------|-------------------|------------------|
| micro | apt | brew |
| glow | apt | brew |
| terminal | kitty (apt) | Tabby (cask) |
| lsd | apt | brew |
| gh, jq, watch | apt | brew |
| watchexec | cargo | brew |
| yazi | release binary → `~/.local/bin` | brew |
| stow | apt | brew |
| JetBrainsMono Nerd Font | manual | brew cask |

## Comandos custom

| Comando | Descrição |
|---------|-----------|
| `y` | Abre yazi; ao sair, `cd` para o diretório selecionado |
| `mdwatch arquivo.md` | Preview live de Markdown com glow + watchexec |
| `view-actions` | Dashboard GitHub Actions (atualiza a cada 15s) |

### GitHub Actions dashboard

Config em `~/.config/ci-status.env` (criado na primeira instalação a partir de `config/ci-status.env.example`):

```bash
ORG=sua-org-github
REPOS=(repo-a repo-b repo-c)
```

Testar manualmente:

```bash
~/.local/bin/ci-status
view-actions
```

## Atalhos de split (kitty / Tabby)

| Atalho | Ação |
|--------|------|
| Ctrl+Shift+E | Split vertical |
| Ctrl+Shift+O | Split horizontal |
| Ctrl+Shift+W | Fechar split |
| Alt+setas | Navegar entre splits |

No macOS o Tabby também mantém os atalhos nativos (`⌘-D` / `⌘-Shift-D`).

## Shell

- **Linux:** bash — `~/.bashrc` + `~/.bash_aliases`
- **macOS:** zsh — `~/.zshrc` + `~/.zsh_aliases`

Lógica compartilhada em `lib/shell-common.sh` (prompt, `y`, `mdwatch`, `view-actions`).

Aliases comuns:

- `ls`, `la`, `lt` → lsd
- `ssh` → `kitten ssh` **somente dentro do kitty** (no Tabby usa `ssh` normal)

## Linux vs macOS

| Item | Linux | macOS |
|------|-------|------|
| Shell default | bash | zsh |
| Terminal | kitty (`~/.config/kitty`) | Tabby (`~/Library/Application Support/tabby`) |
| `date -d` (ci-status) | GNU date nativo | `gdate` via brew `coreutils` |
| Fonte | JetBrainsMono Nerd Font | `font-jetbrains-mono-nerd-font` cask |

## Estrutura do repo

```
dotfiles/
├── install.sh
├── bootstrap/          # apt ou brew
├── packages/            # listas de pacotes
├── home/                # GNU Stow → ~ e ~/.config
│   └── config/tabby/    # + symlink macOS → Application Support
├── lib/shell-common.sh
├── bin/ci-status.sh
└── config/ci-status.env.example
```

## Pós-instalação

Na primeira instalação, arquivos existentes em `~` são movidos para `*.bak-pre-dotfiles` antes do stow criar symlinks.

1. Recarregar shell: `source ~/.bashrc` (Linux) ou `source ~/.zshrc` (Mac)
2. `gh auth login`
3. Abrir Tabby (Mac) ou kitty (Linux) e confirmar a fonte Nerd
4. Testar: `y`, `mdwatch README.md`, `view-actions`

## Migração para Mac (checklist)

```bash
xcode-select --install
git clone https://github.com/guilhermepantoja/dotfiles.git ~/dotfiles
cd ~/dotfiles && ./install.sh
gh auth login
source ~/.zshrc
```

## Segurança

Não versionado: SSH keys, tokens, configs Cursor com auth, `ci-status.env` local (opcional manter privado).

## Licença

MIT — use e adapte livremente.
