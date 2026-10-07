# Installation

## GLFW3
This project relies on the C library **GLFW3** for window creation and interaction. 

### 2. Static Library
You will also need the compiled static library. Choose **one** of the two options below:

#### Option A: Download a Pre-built Binary
1. Download the pre-built binaries for your target system from the [GLFW Downloads page](https://www.glfw.org/download.html).
2. Place the static library into your `{repo_root}/deps/glfw/lib/` directory:
   * **macOS / Linux:** `libglfw3.a`
   * **Windows:** `glfw3.lib` (or MinGW `.a`)

#### Option B: Build from Source (CMake)
Open a terminal in the downloaded GLFW source directory and run:
```bash
mkdir build
cd build
cmake -DBUILD_SHARED_LIBS=OFF ..
cmake --build . --config Release
```
Then, copy the compiled static library into your `{repo_root}/deps/glfw/lib/` directory.

# Running
To run, all that is required is `zig build run`
