let base = ($env.PWD | path basename)

export def left-prompt [] {
  let cur = ($env.PWD | path basename)
  if $cur != $base {
    "\u{001B}[1;34m" + $cur + "/nix-develop-" + $base + "\u{001B}[0m"
  } else {
    "\u{001B}[1;34m" + "nix-develop-" + $base + "\u{001B}[0m"
  }
}

$env.config.show_banner = false
$env.config.edit_mode = 'vi'

$env.PROMPT_COMMAND = {|| left-prompt }
$env.PROMPT_INDICATOR = {|| "> " }
$env.PROMPT_COMMAND_RIGHT = {|| "" }
