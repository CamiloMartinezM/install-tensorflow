import os
import re
import subprocess
import sys
from pathlib import Path

# Set this to True to show complete paths in the output
SHOW_COMPLETE_PATHS = False

# Show contents of the target directories after creating symlinks
SHOW_TARGET_CONTENTS = False

# Get the Python version of the current environment
PYTHON_VERSION = ".".join(map(str, sys.version_info[:2]))

# Get the conda prefix from the environment variable
# Try to get it from CONDA_PREFIX, otherwise use VIRTUAL_ENV
CONDA_PREFIX = os.environ.get("VIRTUAL_ENV")
if not CONDA_PREFIX:
    CONDA_PREFIX = os.environ.get("CONDA_PREFIX")

# Define the target and link names
TENSORRT_LIBS_PATH = os.path.join(
    CONDA_PREFIX, f"lib/python{PYTHON_VERSION}/site-packages/tensorrt_libs"
)
NVIDIA_CUDNN_PATH = os.path.join(
    CONDA_PREFIX, f"lib/python{PYTHON_VERSION}/site-packages/nvidia/cudnn/lib"
)
CUDA_PATH = "/usr/local/cuda/lib64/"

# Check the version of the library before creating the symlink
# If set to False, a symlink could be created such that libnvinfer_plugin.so.8.6.1 points
# to libnvinfer_plugin.so.10
CHECK_VERSION = False

# ANSI escape codes for colors and styling
GREEN = "\033[1;32m"  # Bold green
RED = "\033[1;31m"  # Bold red
YELLOW = "\033[1;33m"  # Bold yellow
BLUE = "\033[34m"  # Actually cyan/light blue which is often more readable than deep blue
RESET = "\033[0m"  # Reset color and style

# Larger, bold stylized symbols with colors
INFO = f"{BLUE}🛈{RESET}"  # Large information symbol
ERROR = f"{RED}✘{RESET}"  # Large X symbol
WARN = f"{YELLOW}⚠{RESET}"  # Large warning symbol


def print_log(message: str, level: str = "INFO", end="\n") -> None:
    """Print a log message with the appropriate colored symbol.

    Parameters
    ----------
        message : str
            String message to log
        level : str (default: "INFO")
            String ('INFO', 'ERROR', or 'WARN')

    Raises
    ------
        ValueError
            If the log level is not one of 'INFO', 'ERROR', or 'WARN'
    """
    if level == "":
        print(message, end=end)
    elif level not in ["INFO", "ERROR", "WARN"]:
        raise ValueError("Invalid log level. Use 'INFO', 'ERROR', or 'WARN'.")
    else:
        symbols = {"INFO": INFO, "ERROR": ERROR, "WARN": WARN}
        symbol = symbols.get(level.upper(), INFO)
        bold_level = f"\033[1m{level}\033[0m"
        print(f"{symbol} {bold_level}: {message}", end=end)


def ppath(path: Path | str, color=True, override_long=False) -> str:
    """Prints a shortened the path by removing the common prefix. If `override_long` is set to True, it will print the
    complete path, even if `SHOW_COMPLETE_PATHS` is set to `False`. By default, it colors the path.

    For example: `/home/user/anaconda3/lib/python3.8/site-packages/tensorrt_libs/file -> tensorrt_libs/file`
    """
    if not SHOW_COMPLETE_PATHS and not override_long:
        shortened = str(path).replace(
            os.path.join(CONDA_PREFIX, f"lib/python{PYTHON_VERSION}/site-packages/"), ""
        )
    else:
        shortened = str(path)
    return f"{BLUE}{shortened}{RESET}" if color else shortened


def create_sudo_symlink(link_path: Path, target_path: Path) -> bool:
    """Create a symlink using sudo if necessary.

    Parameters
    ----------
        link_path : Path
            Path where the symlink should be created
        target_path : Path
            Path that the symlink should point to

    Returns
    -------
        bool: True if successful, False otherwise
    """
    try:
        # First try creating the symlink directly
        link_path.symlink_to(target_path)
        return True
    except FileExistsError:
        # If the file already exists, remove it and create the symlink
        remove_sudo_symlink(link_path)
        create_sudo_symlink(link_path, target_path)
        return True
    except PermissionError:
        try:
            # If permission denied, try using sudo
            cmd = ["sudo", "ln", "-s", str(target_path.absolute()), str(link_path.absolute())]
            result = subprocess.run(cmd, capture_output=True, text=True)

            if result.returncode != 0:
                raise Exception(f"Sudo command failed: {result.stderr}")
            return True
        except Exception as e:
            print_log(f"Failed to create symlink even with sudo: {e}", "ERROR")
            return False


def remove_sudo_symlink(link_path: Path) -> bool:
    """Remove a symlink using sudo if necessary.

    Parameters
    ----------
        link_path : Path
            Path to the symlink to be removed

    Returns
    -------
        bool:
            True if successful, False otherwise
    """
    try:
        # First try removing normally
        link_path.unlink()
        return True
    except PermissionError:
        try:
            # If permission denied, try using sudo
            cmd = ["sudo", "rm", str(link_path)]
            result = subprocess.run(cmd, capture_output=True, text=True)

            if result.returncode != 0:
                raise Exception(f"Sudo command failed: {result.stderr}")
            return True
        except Exception as e:
            print_log(f"Failed to remove symlink even with sudo: {e}", "ERROR")
            return False


def parse_required_libs(strace_output):
    """Parse strace output to find missing TensorRT libraries."""
    libs = set()
    # Corrected Pattern:
    # - Captures the full library name 'libnvinfer....so.X' directly.
    # - (?:_plugin)? is a non-capturing group to optionally match '_plugin'.
    # - \.so\.(\d+) matches '.so.' followed by one or more digits (like '7').
    pattern = r"(libnvinfer(?:_plugin)?\.so\.\d+)"

    for line in strace_output.splitlines():
        # We search for the pattern. The 'openat' part is not strictly necessary
        # if we just want the library name.
        match = re.search(pattern, line)
        if match:
            # The entire matched library name is in group 0 or 1 depending on the pattern.
            # Since we put the whole thing in parentheses, it's in group 1.
            lib_name = match.group(1)
            libs.add(lib_name)

    return sorted(list(libs))  # Sorting for consistent output


def find_matching_file(
    directory: str, file_basename: str, file_version: str, check_version=CHECK_VERSION
) -> str | None:
    """Find a matching file in the directory based on the basename and version."""
    if not os.path.exists(directory):
        return None

    for f in os.listdir(directory):
        # Use regex to safely find files that start with the base name and get their major version
        # e.g., match 'libnvinfer.so.8' from 'libnvinfer.so.8.6.1'
        match = re.match(f"^{re.escape(file_basename)}({file_version}\\..*)", f)
        if match:
            # Check for broken symlinks
            full_path = os.path.join(directory, f)
            if os.path.islink(full_path) and not os.path.exists(full_path):
                continue
            return f  # Return the first valid match

    # If check_version is disabled, we can be more lenient
    if not check_version:
        for f in os.listdir(directory):
            if f.startswith(file_basename):
                # Check for broken symlinks
                full_path = os.path.join(directory, f)
                if os.path.islink(full_path) and not os.path.exists(full_path):
                    continue
                print_log(
                    f"Version mismatch for {file_basename + file_version}: Found {f}, but "
                    "continuing since CHECK_VERSION is disabled.",
                    "WARN",
                )
                return f
    return None


def check_and_create_symlinks(
    missing_libs: list[str],
    target_dir: str,
    tensorrt_libs_as_default=False,
    check_version=CHECK_VERSION,
) -> list[tuple[Path, Path]]:
    """Create symlinks to the files in `missing_libs` in the `target_dir`.

    Parameters
    ----------
        missing_libs : list[str]
            List of missing libraries to create symlinks for
        target_dir : str
            Target directory to create symlinks in
        tensorrt_libs_as_default : bool (default: False)
            If set to True, it will default to TensorRT libs path if the file is not found in the target directory. This
            assumes that the TensorRT libraries are installed in the conda environment and that the path contains the
            files in `missing_libs`.
        check_version : bool (default: True)
            If set to True, it will check for the version of the library before creating the symlink

    Returns
    -------
        created_links : list[tuple[Path, Path]]
            List of tuples containing the symlink path and the target path
    """
    created_links = []
    for lib in missing_libs:
        # Corrected Regex:
        # ^(lib.+?\.so\.)  -> Captures the base name, e.g., "libnvinfer.so."
        # (\d+)            -> Captures the major version number, e.g., "7" or "8"
        # The rest of the version string (e.g., ".6.1") is ignored, which is fine.
        match = re.match(r"^(lib.+?\.so\.)(\d+)", lib)
        if not match:
            print_log(f"Could not parse library format: {lib}", "ERROR")
            continue

        lib_base_name = match.group(1)  # e.g., 'libnvinfer.so.'
        lib_version = match.group(2)  # e.g., '7'
        target_file = None
        source_dir = target_dir

        # Check for the matching base name and version in the target directory
        target_file = find_matching_file(target_dir, lib_base_name, lib_version, check_version)

        # If no matching file found in the target directory, default to TensorRT libs path
        if not target_file:
            print_log(
                f"Could not find a matching file for {lib} in {ppath(target_dir)}", "WARN", end=""
            )

            if tensorrt_libs_as_default:
                print_log(f", defaulting to {ppath(TENSORRT_LIBS_PATH)} path.", "")
                source_dir = TENSORRT_LIBS_PATH
                target_file = lib
            else:
                print_log(", skipping.", "")
                continue

        # Create symbolic link
        link_path = Path(target_dir) / lib  # This is the missing link path
        symlinks_to_path = (
            Path(source_dir) / target_file
        )  # This is the path to the file to be linked

        # Make sure symlinks_to_path exists
        if not symlinks_to_path.exists():
            print_log(
                f"File to symlink to not found: {ppath(symlinks_to_path)}, skipping.", "ERROR"
            )
            continue

        # Check if the symlink already exists and is correct
        if link_path.exists():
            if link_path.is_symlink() and os.readlink(link_path) == str(symlinks_to_path):
                print_log(
                    f"Symlink already exists and is correct: {ppath(link_path)} -> {ppath(symlinks_to_path)}",
                    "INFO",
                )
                continue
            elif (
                link_path.is_symlink()
                and os.readlink(link_path) != str(symlinks_to_path)
                and os.readlink(link_path).startswith(TENSORRT_LIBS_PATH)
                and tensorrt_libs_as_default
            ):
                print_log(
                    f"Symlink exists defaulting to {ppath(TENSORRT_LIBS_PATH)} path, "
                    + f"{ppath(link_path)} -> {ppath(os.readlink(link_path))}",
                    "WARN",
                )
                continue
            else:
                print_log(f"Symlink exists but is incorrect: {ppath(link_path)}", "WARN")
                link_path.unlink()

        # Check if the symlink is a broken link
        if os.path.exists(link_path) and not os.path.exists(os.readlink(link_path)):
            print_log(f"Broken symlink found: {ppath(link_path)}, removing it", "WARN")
            if not remove_sudo_symlink(link_path):
                print_log(f"Failed to remove broken symlink: {ppath(link_path)}", "ERROR")
                continue  # Skip to next iteration if we couldn't remove it

        # Create the symlink with sudo if necessary
        if create_sudo_symlink(link_path, symlinks_to_path):
            print_log(f"Created symlink: {ppath(link_path)} -> {ppath(symlinks_to_path)}", "INFO")
            created_links.append((link_path, symlinks_to_path))
        else:
            print_log(f"Failed to create symlink for {lib}", "ERROR")

    return created_links


def main():
    if not CONDA_PREFIX:
        print_log("CONDA_PREFIX is not set. Activate your environment and try again.", "ERROR")
        sys.exit(1)
    else:
        print_log(f"Environment: {CONDA_PREFIX}", "INFO")

    # Target directories to create symlinks in
    target_dirs = [TENSORRT_LIBS_PATH, NVIDIA_CUDNN_PATH]  # , CUDA_PATH]

    # Run the strace command and parse required libraries
    try:
        strace_cmd = ["strace", "-e", "open,openat", "python", "-c", "import tensorflow as tf"]
        result = subprocess.run(
            strace_cmd, stderr=subprocess.PIPE, stdout=subprocess.PIPE, text=True
        )
        strace_output = result.stderr
    except Exception as e:
        print_log(f"Error running strace command: {e}", "ERROR")
        return

    required_libs = parse_required_libs(strace_output)

    if not required_libs:
        print_log("No missing libraries found in strace output.", "ERROR")
        print_log("Original strace output [-1000:]:", "INFO")
        print_log(strace_output[-1000:], "")
        return

    print_log(f"Required libraries to link: {required_libs}", "INFO")

    # Create symbolic links for required libraries
    for target_dir in target_dirs:
        # Make sure the target directory exists
        if not os.path.exists(target_dir):
            print_log(f"Target directory does not exist: {ppath(target_dir)}", "ERROR")
            continue

        created_links = check_and_create_symlinks(
            required_libs, target_dir, tensorrt_libs_as_default=True
        )
        if created_links:
            print_log("Summary of created symlinks:", "INFO")
            for link, target in created_links:
                print_log(f"\t* {ppath(link)} -> {ppath(target)}", "")
        else:
            print_log("No symlinks were created.", "WARN")

        if SHOW_TARGET_CONTENTS:
            print_log(f"Contents of {ppath(target_dir, override_long=True)} (ls output):", "INFO")
            try:
                ls_output = subprocess.check_output(["ls", "-l", target_dir], text=True)
                print_log(ls_output, "")
            except Exception as e:
                print_log(f"Error running ls command: {e}", "ERROR")
                return


if __name__ == "__main__":
    main()
