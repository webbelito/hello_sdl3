package build

import "core:log"
import "core:strings"
import "core:slice"
import "core:path/filepath"
import os "core:os/os2"

// The name of the executable
EXE :: "hello_sdl3"

// The output executable
OUT :: EXE + ".exe" when ODIN_OS == .Windows else EXE

main :: proc() {
    
    // Initialize the logger
    context.logger = log.create_console_logger()

    // Build the executable
    run_str("odin build src -debug -out:" + OUT + " --error-pos-style:unix")

    // Create a bin directory if it doesn't exist
    if !os.exists("bin") {
        dir_err := os.make_directory("bin")
        if dir_err != nil {
            log.errorf("Error creating bin directory: {}", dir_err)
            os.exit(1)
        }
    }

    // Create the shaders/bin directory if it doesn't exist
    if !os.exists("assets/shaders/bin") {
        dir_err := os.make_directory("assets/shaders/bin")
        if dir_err != nil {
            log.errorf("Error creating shaders/bin directory: {}", dir_err)
            os.exit(1)
        }
    }

    // Read all the files in the shaders/src directory
    files, err := os.read_all_directory_by_path("assets/shaders/src", context.temp_allocator)
    if err != nil {
        log.errorf("Error reading shaders directory: {}", err)
        os.exit(1)
    }

    // Compile all the shaders
    for shader in files {
        shadercross(shader, "spv")
        shadercross(shader, "dxil")
        shadercross(shader, "msl")
        shadercross(shader, "json")
    }

    // Run the executable if the "run" argument is provided
    if slice.contains(os.args, "run") do run({ OUT })
}

// Compile a shader file to a given format
shadercross :: proc(file: os.File_Info, format: string) {
    basename := filepath.stem(file.name)
    outfile := filepath.join({"assets/shaders/bin", strings.concatenate({basename, ".", format})})
    run({ "shadercross", file.fullpath, "-o", outfile })
}

// Split a command string into a command and arguments
run_str :: proc(cmd: string) {
    run(strings.split(cmd, " "))
}

// Run a command
run :: proc(cmd: []string) {
    log.infof("Running {}", cmd)
    code, err := exec(cmd)

    if err != nil {
        log.errorf("Error executing process: {}", err)
        os.exit(1)
    }

    if code != 0 {
        log.errorf("Process exited with non-zero code: {}", code)
        os.exit(1)
    }
}

// Execute a command and return the exit code
exec :: proc(cmd: []string) -> (code: int, error: os.Error) {
    process := os.process_start({ command = cmd, stdin = os.stdin, stdout = os.stdout, stderr = os.stderr }) or_return
    state := os.process_wait(process) or_return
    os.process_close(process) or_return

    return state.exit_code, nil
}