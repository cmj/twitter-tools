## kitty-tweet

Print tweets in kitty terminal

![](https://i.imgur.com/vRQT1xB.png)

### Add an `@username` command to display tweets

Add the following function to `~/.bashrc`:

```bash
command_not_found_handle() {
    if [[ $1 =~ ^@[^[:space:]]+$ ]]; then
        kitty-tweet.sh "$@"
        return $?
    fi

    echo "bash: $1: command not found" >&2
    return 127
}
```
