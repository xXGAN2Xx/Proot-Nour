import os
import sys
import urllib.request
import urllib.error
import urllib.parse
import subprocess
import tempfile
import shutil
import traceback
import threading

NOUR_SCRIPT_NAME = "nour.sh"
NOUR_URL = "https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/nour.sh"

def main():
    print("Done (s)! For help, type help")

    try:
        if handle_script(NOUR_SCRIPT_NAME, NOUR_URL):
            return

        print(f"'{NOUR_SCRIPT_NAME}' not found locally. Attempting to download...")
        downloaded_file = download_and_set_permissions(NOUR_URL, NOUR_SCRIPT_NAME)
        if downloaded_file is not None:
            print(f"Preparing to run downloaded '{os.path.basename(downloaded_file)}'...")
            run_script(downloaded_file)
        else:
            print(f"Failed to download or set permissions for '{NOUR_SCRIPT_NAME}'. Script will not be run.")

    except Exception as e:
        print(f"An unexpected error occurred in main: {e}")
        traceback.print_exc()

def handle_script(script_name: str, script_url: str) -> bool:
    if not os.path.exists(script_name):
        return False

    print(f"Found '{os.path.basename(script_name)}'. Checking for updates...")
    was_successfully_updated = False
    is_up_to_date_and_skipping_perm_set = False

    if is_file_changed(script_name, script_url):
        print(f"'{os.path.basename(script_name)}' has changed or an error occurred during check. Attempting to download the new version...")
        updated_file = download_and_set_permissions(script_url, script_name)
        if updated_file is not None:
            file_to_execute = updated_file
            was_successfully_updated = True
            is_up_to_date_and_skipping_perm_set = False
            print(f"Successfully updated '{os.path.basename(script_name)}'.")
        else:
            print(f"Failed to update '{os.path.basename(script_name)}'. Will attempt to run the existing local version '{os.path.basename(script_name)}'.")
            file_to_execute = script_name
            was_successfully_updated = False
            is_up_to_date_and_skipping_perm_set = False
    else:
        print(f"'{os.path.basename(script_name)}' is up to date.")
        file_to_execute = script_name
        was_successfully_updated = False
        is_up_to_date_and_skipping_perm_set = True

    can_run = False

    if was_successfully_updated:
        if os.access(file_to_execute, os.X_OK):
            print(f"Permissions for updated '{os.path.basename(file_to_execute)}' were set during download.")
            can_run = True
        else:
            print(f"Error: Updated file '{os.path.basename(file_to_execute)}' is not executable despite successful update. Cannot run.")
    elif is_up_to_date_and_skipping_perm_set:
        print(f"Skipping explicit permission setting for up-to-date file '{os.path.basename(file_to_execute)}'.")
        if os.access(file_to_execute, os.X_OK):
            print(f"'{os.path.basename(file_to_execute)}' is already executable.")
            can_run = True
        else:
            print(f"Warning: Up-to-date file '{os.path.basename(file_to_execute)}' is NOT executable. Script will not be run.")
            can_run = False
    else:
        print(f"Attempting to set/verify permissions for '{os.path.basename(file_to_execute)}'...")
        if set_executable_permission(file_to_execute):
            if os.access(file_to_execute, os.X_OK):
                print(f"Permissions set successfully for '{os.path.basename(file_to_execute)}'.")
                can_run = True
            else:
                print("Error: permissions set but file is not executable. Cannot run.")
        else:
            print(f"Failed to set executable permission for '{os.path.basename(file_to_execute)}'. Script will not be run.")

    if can_run:
        print(f"Preparing to run '{os.path.basename(file_to_execute)}' with Auto-Input...")
        run_script(file_to_execute)
    else:
        print(f"Script '{os.path.basename(file_to_execute)}' will not be run due to permission issues.")
    
    return True

def is_file_changed(local_file: str, remote_url: str) -> bool:
    print(f"Comparing local '{os.path.basename(local_file)}' with remote '{remote_url}'...")
    try:
        with urllib.request.urlopen(remote_url) as response:
            remote_content = response.read().decode('utf-8')
        with open(local_file, 'r', encoding='utf-8') as f:
            local_content = f.read()
        
        changed = remote_content != local_content
        if changed:
            print(f"Contents differ for '{os.path.basename(local_file)}'.")
        else:
            print(f"Contents are the same for '{os.path.basename(local_file)}'.")
        return changed
    except Exception as e:
        print(f"Error during comparison: {e}. Assuming file changed.")
        return True

def download_and_set_permissions(script_url_string: str, script_file_name: str) -> str | None:
    url_parsed = urllib.parse.urlparse(script_url_string)
    if not url_parsed.scheme or not url_parsed.netloc:
        print(f"Error: Invalid URL format: {script_url_string}")
        return None

    print(f"Downloading '{os.path.basename(script_file_name)}' from {script_url_string}...")
    try:
        download_file(script_url_string, script_file_name)
        print(f"Download completed for '{os.path.basename(script_file_name)}'.")
    except Exception as e:
        print(f"Error downloading '{os.path.basename(script_file_name)}': {e}")
        traceback.print_exc()
        return None

    if not set_executable_permission(script_file_name):
        print("Download succeeded but setting permissions failed.")
        return None
    
    print(f"Successfully downloaded and ensured permissions for '{os.path.basename(script_file_name)}'.")
    return script_file_name

def set_executable_permission(file_path: str) -> bool:
    if not os.path.exists(file_path):
        return False
    
    print(f"Setting executable permission on '{os.path.basename(file_path)}'...")
    try:
        result = subprocess.run(["chmod", "+x", os.path.abspath(file_path)])
        return result.returncode == 0
    except Exception as e:
        traceback.print_exc()
        return False

def run_script(script_file: str):
    if not os.access(script_file, os.X_OK):
        print(f"Cannot run script: '{os.path.basename(script_file)}' is not executable.")
        return

    print(f"Running '{os.path.basename(script_file)}' and waiting for it to complete...")
    try:
        # Start the process, piping stdin so we can write to it, and merging stderr into stdout
        process = subprocess.Popen(["bash", os.path.abspath(script_file)],
            stdin=subprocess.PIPE,
            stdout=sys.stdout,
            stderr=subprocess.STDOUT
        )

        # Auto-input commands
        if process.stdin:
            process.stdin.write(b"1\n")
            process.stdin.flush()

            process.stdin.write(b"4\n")
            process.stdin.flush()

            process.stdin.write(b"bash //sing-box.sh\n")
            process.stdin.flush()

        # Background thread to forward standard input to the process
        def forward_stdin():
            try:
                while True:
                    # Read up to 1024 bytes from standard input
                    data = os.read(sys.stdin.fileno(), 1024)
                    if not data:
                        break
                    if process.stdin:
                        process.stdin.write(data)
                        process.stdin.flush()
            except Exception:
                pass # Ignore broken pipes or closed streams

        input_thread = threading.Thread(target=forward_stdin, daemon=True)
        input_thread.start()

        exit_code = process.wait()
        print(f"'{os.path.basename(script_file)}' finished with exit code {exit_code}.")

        if exit_code == 0:
            print("Script completed successfully. Exiting program...")
            sys.exit(0)

    except OSError as e:
        print(f"IOException running script: {e}")
        traceback.print_exc()
    except KeyboardInterrupt:
        print("Script execution interrupted.")

def download_file(url: str, destination: str):
    dest_dir = os.path.dirname(os.path.abspath(destination)) or "."
    dest_name = os.path.basename(destination)
    
    fd, temp_file_path = tempfile.mkstemp(dir=dest_dir, prefix=dest_name, suffix=".tmpdownload")
    os.close(fd)
    
    try:
        with urllib.request.urlopen(url) as response, open(temp_file_path, 'wb') as out_file:
            shutil.copyfileobj(response, out_file)
        os.replace(temp_file_path, destination)
    except Exception as e:
        if os.path.exists(temp_file_path):
            try:
                os.remove(temp_file_path)
            except OSError:
                pass
        raise IOError("Failed to download file") from e
    finally:
        if os.path.exists(temp_file_path):
            try:
                os.remove(temp_file_path)
            except OSError:
                pass

if __name__ == "__main__":
    main()
