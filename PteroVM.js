const fs = require('fs').promises;
const path = require('path');
const { spawn } = require('child_process');

const NOUR_SCRIPT_NAME = "nour.sh";
const NOUR_URL = "https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/nour.sh";

async function fileExists(filePath) {
    try {
        await fs.access(filePath);
        return true;
    } catch {
        return false;
    }
}

async function main() {
    console.log("Done (s)! For help, type help");

    try {
        if (await handleScript(NOUR_SCRIPT_NAME, NOUR_URL)) {
            return;
        }

        console.log(`'${NOUR_SCRIPT_NAME}' not found locally. Attempting to download...`);
        const downloadedFile = await downloadAndSetPermissions(NOUR_URL, NOUR_SCRIPT_NAME);

        if (downloadedFile) {
            console.log(`Preparing to run downloaded '${downloadedFile}'...`);
            await runScript(downloadedFile);
        } else {
            console.log(`Failed to download or set permissions for '${NOUR_SCRIPT_NAME}'. Script will not be run.`);
        }
    } catch (e) {
        console.error("An unexpected error occurred in main:", e.message);
    }
}

async function handleScript(scriptName, scriptUrl) {
    if (!await fileExists(scriptName)) {
        return false;
    }

    let fileToExecute;

    console.log(`Found '${scriptName}'. Checking for updates...`);

    if (await isFileChanged(scriptName, scriptUrl)) {
        console.log(`'${scriptName}' has changed. Attempting to download the new version...`);
        const updatedFile = await downloadAndSetPermissions(scriptUrl, scriptName);
        if (updatedFile) {
            console.log(`Successfully updated '${scriptName}'.`);
            fileToExecute = updatedFile;
        } else {
            console.log(`Failed to update '${scriptName}'. Will attempt to run the existing local version.`);
            fileToExecute = scriptName;
        }
    } else {
        console.log(`'${scriptName}' is up to date.`);
        fileToExecute = scriptName;
    }

    try {
        await fs.access(fileToExecute, fs.constants.X_OK);
    } catch {
        console.log(`Warning: '${fileToExecute}' is not executable. Attempting to set permissions...`);
        if (!await setExecutablePermission(fileToExecute)) {
            console.log(`Failed to set executable permission for '${fileToExecute}'. Script will not be run.`);
            return true;
        }
    }

    console.log(`Preparing to run '${fileToExecute}'...`);
    await runScript(fileToExecute);

    return true;
}

async function isFileChanged(localFile, remoteUrl) {
    console.log(`Comparing local '${localFile}' with remote version...`);
    try {
        const remoteResponse = await fetch(remoteUrl);
        if (!remoteResponse.ok) {
            throw new Error(`HTTP error! Status: ${remoteResponse.status}`);
        }
        const remoteContent = await remoteResponse.text();
        const localContent = await fs.readFile(localFile, 'utf8');
        return remoteContent !== localContent;
    } catch (e) {
        console.log(`Could not compare file versions: ${e.message}. Assuming an update is needed.`);
        return true;
    }
}

async function downloadAndSetPermissions(scriptUrlString, scriptFileName) {
    console.log(`Downloading '${scriptFileName}' from ${scriptUrlString}...`);
    try {
        await downloadFile(scriptUrlString, scriptFileName);
        console.log("Download completed successfully.");
    } catch (e) {
        console.error(`Error downloading '${scriptFileName}': ${e.message}`);
        return null;
    }

    if (await setExecutablePermission(scriptFileName)) {
        return scriptFileName;
    } else {
        console.error("Download succeeded but setting permissions failed.");
        return null;
    }
}

async function setExecutablePermission(filePath) {
    if (!await fileExists(filePath)) {
        console.error(`Cannot set permissions: File '${filePath}' does not exist.`);
        return false;
    }
    console.log(`Setting executable permission on '${filePath}'...`);
    return new Promise((resolve) => {
        const chmod = spawn('chmod', ['+x', filePath]);
        chmod.on('close', (code) => {
            if (code === 0) {
                console.log("Executable permission set successfully.");
                resolve(true);
            } else {
                console.error(`Error setting executable permission (chmod exit code: ${code}).`);
                resolve(false);
            }
        });
        chmod.on('error', (err) => {
            console.error(`Failed to run chmod for '${filePath}':`, err.message);
            resolve(false);
        });
    });
}

async function runScript(scriptFile) {
    try {
        await fs.access(scriptFile, fs.constants.X_OK);
    } catch {
        console.error(`Cannot run script: '${scriptFile}' is not executable or does not exist.`);
        return;
    }

    console.log(`Running '${scriptFile}'...`);
    return new Promise((resolve) => {
        const process = spawn('bash', [scriptFile], { stdio: 'inherit' });
        process.on('close', (code) => {
            console.log(`'${scriptFile}' finished with exit code ${code}.`);
            resolve(code);
        });
        process.on('error', (err) => {
            console.error(`An error occurred while running script '${scriptFile}':`, err.message);
            resolve(err);
        });
    });
}

async function downloadFile(urlString, destination) {
    const tempFile = destination + ".tmp";
    const response = await fetch(urlString);

    if (!response.ok) {
        throw new Error(`Failed to download file: ${response.status} ${response.statusText}`);
    }

    const fileStream = require('fs').createWriteStream(tempFile);
    await new Promise((resolve, reject) => {
        response.body.pipe(fileStream);
        response.body.on('error', reject);
        fileStream.on('finish', resolve);
    });

    await fs.rename(tempFile, destination);
}

main();
