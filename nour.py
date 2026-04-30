import os
import subprocess
import urllib.request
import urllib.error
import shutil
import tempfile
import sys
import traceback

NOUR_SCRIPT_NAME = "nour.sh"
NOURD_SCRIPT_NAME = "nourd.sh"
NOUR_URL = "https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/main/nour.sh"
NOURD_URL = "https://raw.githubusercontent.com/xXGAN2Xx/proot-nour/main/nourd.sh"

def download_file(url_str: str, destination_path: str):
    """
    Downloads a file from url_str to destination_path atomically.
    Downloads to a temporary file first, then moves it to the final destination.
    """
    dest_dir = os.path.dirname(destination_path) or "."
    os.makedirs(dest_dir, exist_ok=True)

    temp_file_path = None
    try:
        with tempfile.NamedTemporaryFile(mode='wb', delete=False, dir=dest_dir, 
                                         prefix=os.path.basename(destination_path) + "_", 
                                         suffix=".tmpdownload") as temp_f:
            temp_file_path = temp_f.name
            with urllib.request.urlopen(url_str) as response:
                shutil.copyfileobj(response, temp_f)
        
        shutil.move(temp_file_path, destination_path)
    
    except Exception as e:
        if temp_file_path and os.path.exists(temp_file_path):
            try:
                os.remove(temp_file_path)
            except OSError as oe:
                print(f"Warning: Failed to delete temporary file '{temp_file_path}' during error handling: {oe}")
        raise IOError(f"Failed to download or replace file '{os.path.basename(destination_path)}' from {url_str}: {e}") from e
    
    finally:
        if temp_file_path and os.path.exists(temp_file_path):
            try:
                os.remove(temp_file_path)
            except OSError:
                print(f"Warning: Temporary file '{temp_file_path}' may still exist and could not be cleaned up in finally block.")


def set_executable_permission(file_path: str) -> bool:
    """Sets executable permission on the given file, similar to 'chmod +x'."""
    abs_file_path = os.path.abspath(file_path)
    if not os.path.exists(abs_file_path):
        print(f"Cannot set permissions: File '{os.path.basename(file_path)}' does not exist at path '{abs_file_path}'.")
        return False

    print(f"Setting executable permission on '{os.path.basename(file_path)}'...")
    try:
        process = subprocess.run(["chmod", "+x", abs_file_path], 
                                 capture_output=True, text=True, check=False)
        if process.returncode != 0:
            print(f"Error setting executable permission for '{os.path.basename(file_path)}' (chmod exit code: {process.returncode}).")
            if process.stderr: print(f"chmod stderr: {process.stderr.strip()}")
            if process.stdout: print(f"chmod stdout: {process.stdout.strip()}")
            return False
        else:
            print(f"Executable permission set for '{os.path.basename(file_path)}'.")
            return True
    except FileNotFoundError:
        print(f"Warning: 'chmod' command not found. Attempting fallback using Python's os.chmod.")
        try:
            current_mode = os.stat(abs_file_path).st_mode
            new_mode = current_mode | 0o111 
            os.chmod(abs_file_path, new_mode)
            print(f"Fallback: Successfully set executable permission for '{os.path.basename(file_path)}' using os.chmod.")
            return True
        except Exception as e_chmod:
            print(f"Fallback os.chmod also failed for '{os.path.basename(file_path)}': {e_chmod}")
            return False
    except (IOError, OSError) as e:
        print(f"OS error while trying to run chmod for '{os.path.basename(file_path)}': {e}")
        return False
    except Exception as e:
        print(f"Unexpected error during chmod for '{os.path.basename(file_path)}': {e}")
        traceback.print_exc()
        return False


def download_and_set_permissions(script_url: str, script_file_name: str) -> str | None:
    """Downloads a script, sets executable permissions, and returns its path on success."""
    print(f"Downloading '{script_file_name}' from {script_url}...")
    try:
        download_file(script_url, script_file_name)
        print(f"Download completed for '{script_file_name}'.")
    except IOError as e:
        print(f"Error downloading '{script_file_name}': {e}")
        return None
    except Exception as e:
        print(f"Unexpected error downloading '{script_file_name}': {e}")
        traceback.print_exc()
        return None

    if not set_executable_permission(script_file_name):
        print(f"Download of '{script_file_name}' succeeded but setting permissions failed.")
        return None
    
    print(f"Successfully downloaded and ensured permissions for '{script_file_name}'.")
    return script_file_name


def is_file_changed(local_file_path: str, remote_url: str) -> bool:
    """Compares local file content with remote URL content. Returns True if different or error."""
    print(f"Comparing local '{os.path.basename(local_file_path)}' with remote '{remote_url}'...")
    try:
        with urllib.request.urlopen(remote_url) as response:
            remote_content_bytes = response.read()
            remote_content = remote_content_bytes.decode('utf-8')
        
        with open(local_file_path, 'rb') as f_local_bytes:
            local_content_bytes = f_local_bytes.read()
            local_content = local_content_bytes.decode('utf-8')
            
        changed = remote_content != local_content
        if changed:
            print(f"Contents differ for '{os.path.basename(local_file_path)}'.")
        else:
            print(f"Contents are the same for '{os.path.basename(local_file_path)}'.")
        return changed
    except (urllib.error.URLError, urllib.error.HTTPError, IOError, UnicodeDecodeError) as e:
        print(f"Error during comparison for '{os.path.basename(local_file_path)}': {e}. Assuming it has changed to be safe.")
        return True
    except Exception as e:
        print(f"Unexpected error comparing file '{os.path.basename(local_file_path)}' with remote: {e}. Assuming it has changed.")
        traceback.print_exc()
        return True


def run_script(script_file_path: str):
    """Runs the specified script file using 'bash'."""
    abs_script_path = os.path.abspath(script_file_path)
    if not os.path.exists(abs_script_path):
        print(f"Cannot run script: '{os.path.basename(script_file_path)}' does not exist at {abs_script_path}.")
        return
    
    if not os.access(abs_script_path, os.X_OK):
        print(f"Cannot run script: '{os.path.basename(script_file_path)}' is not executable. Path: {abs_script_path}")
        return

    print(f"Running '{os.path.basename(script_file_path)}' (path: {abs_script_path}) and waiting for it to complete...")
    try:
        process = subprocess.run(["bash", abs_script_path], check=False)
        print(f"'{os.path.basename(script_file_path)}' finished with exit code {process.returncode}.")
    except FileNotFoundError:
        print(f"Error: 'bash' command not found. Cannot run script '{os.path.basename(script_file_path)}'.")
    except OSError as e:
        print(f"OS error while trying to run script '{os.path.basename(script_file_path)}': {e}")
    except Exception as e:
        print(f"Unexpected error running script '{os.path.basename(script_file_path)}': {e}")
        traceback.print_exc()


def handle_download_choice_set_perms_and_run():
    """Prompts user to choose a script to download, then downloads, sets permissions, and runs it."""
    print("Choose an option to download:")
    print(f"0: Download {NOUR_SCRIPT_NAME}")
    print(f"1: Download {NOURD_SCRIPT_NAME}")
    
    try:
        choice = input("Enter your choice (0 or 1): ").strip()
    except EOFError:
        print("\nNo input received (EOF). Exiting.")
        return

    script_url_to_download: str
    script_name_to_download: str

    if choice == "0":
        script_url_to_download = NOUR_URL
        script_name_to_download = NOUR_SCRIPT_NAME
    elif choice == "1":
        script_url_to_download = NOURD_URL
        script_name_to_download = NOURD_SCRIPT_NAME
    else:
        print("Invalid choice. Please enter 0 or 1. Exiting.")
        return

    downloaded_file_path = download_and_set_permissions(script_url_to_download, script_name_to_download)
    if downloaded_file_path:
        print(f"Preparing to run downloaded '{os.path.basename(downloaded_file_path)}'...")
        run_script(downloaded_file_path)
    else:
        print(f"Failed to download or set permissions for '{script_name_to_download}'. Script will not be run.")


def handle_script(script_name: str, script_url: str) -> bool:
    """
    Manages a single script: checks existence, updates if necessary, sets permissions, and runs.
    Returns True if the script was "handled" (i.e., found locally and processed),
    False if the script was not found locally.
    """
    script_file_path = os.path.abspath(script_name) 
    file_to_execute_path: str | None = None
    
    was_successfully_updated = False
    is_up_to_date_and_local_exists = False

    if os.path.exists(script_file_path):
        print(f"Found '{os.path.basename(script_file_path)}' at '{script_file_path}'. Checking for updates...")
        
        if is_file_changed(script_file_path, script_url):
            print(f"'{os.path.basename(script_file_path)}' has changed or an error occurred. Attempting to download new version...")
            updated_file = download_and_set_permissions(script_url, script_file_path)
            if updated_file:
                file_to_execute_path = updated_file
                was_successfully_updated = True
                print(f"Successfully updated '{os.path.basename(script_file_path)}'.")
            else:
                print(f"Failed to update '{os.path.basename(script_file_path)}'. Will attempt to run the existing local version.")
                file_to_execute_path = script_file_path
        else:
            print(f"'{os.path.basename(script_file_path)}' is up to date.")
            file_to_execute_path = script_file_path
            is_up_to_date_and_local_exists = True
    else:
        return False 

    if file_to_execute_path:
        can_run = False
        
        if not os.path.exists(file_to_execute_path):
             print(f"Error: File '{os.path.basename(file_to_execute_path)}' designated for execution does not exist at '{file_to_execute_path}'. Cannot proceed.")
             return True

        if was_successfully_updated:
            if os.access(file_to_execute_path, os.X_OK):
                print(f"Permissions for updated '{os.path.basename(file_to_execute_path)}' were set during download.")
                can_run = True
            else:
                print(f"Error: Updated file '{os.path.basename(file_to_execute_path)}' is not executable despite successful update. Cannot run.")
        
        elif is_up_to_date_and_local_exists:
            print(f"Skipping explicit permission setting for up-to-date file '{os.path.basename(file_to_execute_path)}'.")
            if os.access(file_to_execute_path, os.X_OK):
                print(f"'{os.path.basename(file_to_execute_path)}' is already executable.")
                can_run = True
            else:
                print(f"Warning: Up-to-date file '{os.path.basename(file_to_execute_path)}' is NOT executable. Permission setting was skipped. Script will not be run.")
                can_run = False
        
        else: 
            print(f"Attempting to set/verify permissions for '{os.path.basename(file_to_execute_path)}' (e.g., fallback scenario)...")
            if set_executable_permission(file_to_execute_path):
                if os.access(file_to_execute_path, os.X_OK):
                    print(f"Permissions set successfully for '{os.path.basename(file_to_execute_path)}'.")
                    can_run = True
                else:
                     print(f"Error: Setting permissions for '{os.path.basename(file_to_execute_path)}' reported successful, but file still not executable. Cannot run.")
            else:
                print(f"Failed to set executable permission for '{os.path.basename(file_to_execute_path)}'. Script will not be run.")

        if can_run:
            print(f"Preparing to run '{os.path.basename(file_to_execute_path)}'...")
            run_script(file_to_execute_path)
        else:
            print(f"Script '{os.path.basename(file_to_execute_path)}' will not be run based on the checks performed.")
        
        return True
    
    print(f"Warning: Reached unexpected state at the end of handle_script for {script_name}.")
    return False


def main():
    try:
        if handle_script(NOUR_SCRIPT_NAME, NOUR_URL):
            return

        if handle_script(NOURD_SCRIPT_NAME, NOURD_URL):
            return

        print(f"Neither '{NOUR_SCRIPT_NAME}' nor '{NOURD_SCRIPT_NAME}' found locally. "
              "Please choose a script to download.")
        handle_download_choice_set_perms_and_run()

    except KeyboardInterrupt:
        print("\nOperation interrupted by user. Exiting.")
        sys.exit(130)
    except Exception as e:
        print(f"An unexpected error occurred in main: {e}")
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()
