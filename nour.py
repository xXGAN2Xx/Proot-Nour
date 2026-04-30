import os
import sys
import urllib.request
import urllib.error
import urllib.parse
import subprocess
import tempfile
import shutil
import traceback

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
            print(f"Error: Updated file '{os.path.basename(file_to_execute)}' is not executable despite successful update and permissioning process. Cannot run.")
    elif is_up_to_date_and_skipping_perm_set:
        print(f"Skipping explicit permission setting for up-to-date file '{os.path.basename(file_to_execute)}'.")
        if os.access(file_to_execute, os.X_OK):
            print(f"'{os.path.basename(file_to_execute)}' is already executable.")
            can_run = True
        else:
            print(f"Warning: Up-to-date file '{os.path.basename(file_to_execute)}' is NOT executable. Permission setting was skipped as requested. Script will not be run.")
            can_run = False
    else:
        print(f"Attempting to set/verify permissions for '{os.path.basename(file_to_execute)}' (e.g., fallback or initial run scenario)...")
        if set_executable_permission(file_to_execute):
            if os.access(file_to_execute, os.X_OK):
                print(f"Permissions set successfully for '{os.path.basename(file_to_execute)}'.")
                can_run = True
            else:
                print(f"Error: Setting permissions for '{os.path.basename(file_to_execute)}' was reported as successful, but the file is still not executable. Cannot run.")
        else:
            print(f"Failed to set executable permission for '{os.path.basename(file_to_execute)}'. Script will not be run.")

    if can_run:
        print(f"Preparing to run '{os.path.basename(file_to_execute)}'...")
        run_script(file_to_execute)
    else:
        print(f"Script '{os.path.basename(file_to_execute)}' will not be run due to permission issues or because it was not made executable.")
    
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
    except (urllib.error.URLError, OSError) as e:
        print(f"IOException during comparison for '{os.path.basename(local_file)}': {e}. Assuming it has changed to be safe.")
        return True
    except Exception as e:
        print(f"Unexpected error comparing file '{os.path.basename(local_file)}' with remote: {e}. Assuming it has changed.")
        traceback.print_exc()
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
        print(f"Download of '{os.path.basename(script_file_name)}' succeeded but setting permissions failed.")
        return None
    
    print(f"Successfully downloaded and ensured permissions for '{os.path.basename(script_file_name)}'.")
    return script_file_name

def set_executable_permission(file_path: str) -> bool:
    if not os.path.exists(file_path):
        print(f"Cannot set permissions: File '{os.path.basename(file_path)}' does not exist at path '{os.path.abspath(file_path)}'.")
        return False
    
    print(f"Setting executable permission on '{os.path.basename(file_path)}'...")
    try:
        result = subprocess.run(["chmod", "+x", os.path.abspath(file_path)], capture_output=True, text=True)
        if result.returncode != 0:
            print(f"Error setting executable permission for '{os.path.basename(file_path)}' (chmod exit code: {result.returncode}).")
            if result.stderr:
                print(f"chmod stderr: {result.stderr.strip()}")
            if result.stdout:
                print(f"chmod stdout: {result.stdout.strip()}")
            return False
        else:
            print(f"Executable permission set for '{os.path.basename(file_path)}'.")
            return True
    except Exception as e:
        print(f"Exception while trying to run chmod for '{os.path.basename(file_path)}': {e}")
        traceback.print_exc()
        return False

def run_script(script_file: str):
    if not os.path.exists(script_file):
        print(f"Cannot run script: '{os.path.basename(script_file)}' does not exist at {os.path.abspath(script_file)}.")
        return
    if not os.access(script_file, os.X_OK):
        print(f"Cannot run script: '{os.path.basename(script_file)}' is not executable. Path: {os.path.abspath(script_file)}")
        return

    print(f"Running '{os.path.basename(script_file)}' and waiting for it to complete...")
    try:
        result = subprocess.run(["bash", os.path.abspath(script_file)])
        print(f"'{os.path.basename(script_file)}' finished with exit code {result.returncode}.")
        
        if result.returncode == 0:
            print("Script completed successfully. Exiting program...")
            sys.exit(0)
    except Exception as e:
        print(f"Exception while trying to run script '{os.path.basename(script_file)}': {e}")
        traceback.print_exc()

def download_file(url: str, destination: str):
    dest_dir = os.path.dirname(os.path.abspath(destination))
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
                print(f"Warning: Failed to delete temporary file: {os.path.abspath(temp_file_path)}")
        raise IOError(f"Failed to download or replace file '{dest_name}' from {url}: {e}") from e
    finally:
        if os.path.exists(temp_file_path):
            temp_size = os.path.getsize(temp_file_path)
            dest_exists = os.path.exists(destination)
            dest_size = os.path.getsize(destination) if dest_exists else 0
            
            if temp_size > 0 and not dest_exists:
                try:
                    os.remove(temp_file_path)
                except OSError:
                    print(f"Warning: Temporary file {os.path.abspath(temp_file_path)} could not be deleted after failed operation.")
            elif not dest_exists or dest_size != temp_size:
                try:
                    os.remove(temp_file_path)
                except OSError:
                    print(f"Warning: Temporary file {os.path.abspath(temp_file_path)} may still exist and could not be cleaned up.")
            else:
                try:
                    os.remove(temp_file_path)
                except OSError:
                    pass

if __name__ == "__main__":
    main()
