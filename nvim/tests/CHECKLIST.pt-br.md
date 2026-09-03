# Checklist pós-atualização

*[English version](CHECKLIST.en.md)*

Rode isto depois de qualquer `:Lazy sync`/`:Lazy update`, `./install.sh --update`,
ou upgrade do próprio Neovim — antes de assumir que os atalhos continuam
funcionando. Cada item aqui nasceu de uma quebra real causada por update de
plugin (principalmente `vim-floaterm`); veja `git log -- nvim/lua/config/keymaps.lua`
para o histórico de cada uma.

## 1. Automatizado (rode primeiro)

```bash
nvim/tests/smoke.sh
```

Verifica: mapeamentos F4–F6 registrados, `RunCode` roda sem erro e a saída
chega no floaterm nos três layouts (vsplit/split/float), `toggleFT` flutuante
não gera erro de argumento. Se isso falhar, já aponta qual `[FAIL]` investigar
antes de ir para os testes manuais abaixo.

Não cobre: nada que dependa de UI real anexada (redraw, `getchar()`,
modo Terminal-mode) — headless não reproduz esse tipo de bug de forma
confiável (descobrimos isso na prática). Por isso a lista manual existe.

## 2. Manual — Floaterm (F4)

Abra qualquer arquivo e teste em terminais diferentes se possível (Konsole
local, e qualquer outro tipo de sessão que você use):

- [ ] `F4` → abre terminal em vsplit vertical
- [ ] `F4` de novo → fecha (toggle)
- [ ] `Shift+F4` → abre terminal em split horizontal
- [ ] `Shift+F4` de novo → fecha
- [ ] `Ctrl+Shift+F4` → abre terminal flutuante (float, ocupando maior parte da tela)
- [ ] `Ctrl+Shift+F4` de novo → fecha
- [ ] Dentro do terminal (modo Terminal-mode), os mesmos atalhos também fecham
      (não só de fora)

Se algum não abrir/fechar: suspeitar de `--wintype=` ou `--autoinsert=`/
`--autoclose=` com valor que o `vim-floaterm` atual não aceita mais —
rodar `:messages` para ver `Argument Error`.

## 3. Manual — Run code, não-interativo (F5)

Use `nvim/tests/hello.c` (ou um `.py` simples) para isolar de problemas
específicos de biblioteca externa (ex.: `-lgmp`):

- [ ] `F5` → compila/roda em vsplit, mostra a saída (não fica em branco/preto)
- [ ] `Shift+F5` → mesma coisa, split horizontal
- [ ] `Ctrl+Shift+F5` → mesma coisa, janela flutuante
- [ ] Depois que aparece `[Process exited N]`, apertar **qualquer tecla**
      fecha o floaterm sozinho e volta pro código
- [ ] Se navegar para outra janela antes de apertar a tecla, a tecla NÃO é
      "roubada" (o floaterm fica aberto até você voltar e apertar algo)
- [ ] Testar também com um programa que dá erro de compilação — o erro
      deve aparecer normalmente (não ficar em branco)

## 4. Manual — Run code, interativo (F6)

Use um `.py` simples:

- [ ] `F6` → compila/roda e cai direto no prompt `>>>` do Python (cursor já
      em modo Terminal-mode, pronto pra digitar — equivalente a apertar `i`)
- [ ] `Shift+F6` / `Ctrl+Shift+F6` → mesma coisa nos outros layouts

Se precisar digitar `i` manualmente pra entrar no prompt: **não** adicione
`--autoinsert=smart` explícito na chamada do `FloatermNew` — passar essa flag
por fora não funcionou na prática (testado ao vivo). Deixar sem a flag, para
o `vim-floaterm` cair no próprio padrão global (`'smart'`), é o que funciona.
- [ ] Digitar algo no prompt funciona normalmente (não está preso em modo Normal)

## 5. Manual — `:checkhealth` / `:LazyHealth`

- [ ] `dap` → adapter `gdb` aparece `OK is executable`, sem erro de
      `Missing required command property`
- [ ] `lazyvim` → `lazygit` encontrado
- [ ] `grug-far` → `ast-grep` encontrado
- [ ] `vim.provider` → Node.js provider mostra pacote `neovim` npm instalado
- [ ] `which-key` → sem duplicata em `<leader>w` (deve ser `<leader>W` para
      salvar; `<leader>w` é o grupo de janelas do LazyVim)

## 6. Manual — Tema claro/escuro

- [ ] Abrir o Neovim normalmente → tema bate com o tema atual do sistema
      (KDE claro → `wbs`; KDE escuro → `catppuccin-mocha`)
- [ ] `<leader>tt` ou `:ToggleTheme` → alterna entre os dois

## Se algo quebrar

1. Ver `git log --oneline -- nvim/lua/config/keymaps.lua` para achar commits
   parecidos (mudança de flag do floaterm já aconteceu 2x).
2. `:messages` logo após o atalho falhar — mensagens de erro do
   `vim-floaterm` aparecem ali, não como erro Lua.
3. Testar em `nvim --headless` com `nvim/tests/smoke.sh` só descarta bugs de
   lógica pura — bugs de renderização (tela preta, cursor não move, etc.)
   só aparecem com UI real anexada; não adianta insistir em depurar isso via
   `--headless`.
