# Get Started

1. **Install dependencies** (on the machine running the script):

   ```bash
   sudo apt install sshfs unison
   ```

2. **Make the script executable**:

   ```bash
   chmod +x remote_sync.sh
   ```

3. **Add the key to your session**:

     ```bash
     eval "$(ssh-agent -s)"
     ssh-add ~/.ssh/id_rsa
     ```

4. **Edit the script**:
   You can set default values like usernames, hostnames, and directories inside the script if you don’t want to pass them as command-line arguments.

5. **Use absolute paths for remote directories** when supplying them via `--directory1` and `--directory2`.
   For example, use:

   ```bash
   --directory1=/home/username/shared --directory2=/home/username/shared
   ```

   ❗Avoid using relative paths like `~/shared` — they may not expand as expected over `sshfs`.

6. **Important Unison behavior**:
   If one of the directories becomes completely empty while in sync, **Unison will abort the operation** to prevent accidentally deleting all files in the other directory. This safety feature protects against destructive syncs.