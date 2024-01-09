package main

// based on https://medium.com/@ssttehrani/containers-from-scratch-with-golang-5276576f9909

import (
	"fmt"
	"os"
	"os/exec"
	"syscall"

	"golang.org/x/sys/unix"
)

const INSIDE_CHROOT = "INSIDE_CHROOT"

func main() {
	_, ns := os.LookupEnv(INSIDE_CHROOT)
	if ns {
		runInNamespace()
	} else {
		run()
	}
}

func run() {
	if len(os.Args) < 3 {
		fmt.Println("Usage: chroot <path> <command> [arguments...]")
		os.Exit(1)
	}

	cmd := exec.Command("/proc/self/exe", os.Args[1:]...)
	cmd.Env = append(cmd.Env,
		fmt.Sprintf("%s=1", INSIDE_CHROOT),
		"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
	)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.SysProcAttr = &syscall.SysProcAttr{
		Cloneflags:
			syscall.CLONE_NEWNET	|	// isolate network
			syscall.CLONE_NEWNS 	|	// isolated mount namespace
			syscall.CLONE_NEWPID	|	// isolated PID namespace (prevents processes escaping)
			syscall.CLONE_NEWUSER	|	// isolated user namespace (prevents access to host users)
			syscall.CLONE_NEWUTS,		// isolated hostname and domainname
	}
	uid := os.Getuid()
	gid := os.Getgid()
	if uid != 0 {
		cmd.SysProcAttr.UidMappings = append(cmd.SysProcAttr.UidMappings, syscall.SysProcIDMap{
			ContainerID: 0,
			HostID:      uid,
			Size:        1,
		})

		cmd.SysProcAttr.GidMappings = append(cmd.SysProcAttr.GidMappings, syscall.SysProcIDMap{
			ContainerID: 0,
			HostID:      gid,
			Size:        1,
		})
	}

	fmt.Fprintln(os.Stderr, "Starting command inside namespace")

	err := cmd.Run()
	if err == nil {
		os.Exit(0)
	}

	if exiterr, ok := err.(*exec.ExitError); ok {
		ws := exiterr.Sys().(syscall.WaitStatus)
		fmt.Println("Command failed with exit code:", ws.ExitStatus())
		os.Exit(int(ws.ExitStatus()))
	}
	fmt.Fprintln(os.Stderr, "Command failed:", err)
	os.Exit(1)
}


func mountProc(chroot string) {
	os.MkdirAll(chroot + "/proc", 0777)

	err := syscall.Mount("proc", chroot + "/proc", "proc", 0, "")
	if err != nil {
		fmt.Println("Failed to mount proc", err)
		os.Exit(1)
	}
}

func mountDevFile(chroot string, filename string) {
	_, err := os.OpenFile(chroot + filename, os.O_RDONLY | os.O_APPEND | os.O_CREATE, 0644)
	if err != nil {
		fmt.Println("Failed to create", filename, err)
		os.Exit(1)
	}
	err = syscall.Mount(filename, chroot + filename, "", unix.MS_BIND | unix.MS_PRIVATE, "")
	if err != nil {
		fmt.Println("Failed to mount", filename, err)
		os.Exit(1)
	}
	fmt.Fprintln(os.Stderr, "mounted in chroot", filename)
}

func runInNamespace() {
	fmt.Fprintln(os.Stderr, "Inside namespace")
	syscall.Sethostname([]byte("inside-container"))

	chroot := os.Args[1]

	fmt.Fprintln(os.Stderr, "mounting chroot")
	mountProc(chroot)

	os.MkdirAll(chroot + "/dev", 0777)
	mountDevFile(chroot, "/dev/urandom")
	mountDevFile(chroot, "/dev/random")
	mountDevFile(chroot, "/dev/null")

	fmt.Fprintln(os.Stderr, "syscall.chroot", chroot)
	err := syscall.Chroot(chroot)
	if err != nil {
		fmt.Println("Failed to chroot:", err)
		os.Exit(1)
	}

	fmt.Fprintln(os.Stderr, "syscall.chdir")
	err = syscall.Chdir("/") // set the working directory inside container
	if err != nil {
		fmt.Println("Failed to chdir:", err)
		os.Exit(1)
	}

	cmd := exec.Command(os.Args[2], os.Args[3:]...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	fmt.Fprintln(os.Stderr, "About to execute:", os.Args[2:])
	err = cmd.Run()
	exitStatus := 0

	if err != nil {
		if exiterr, ok := err.(*exec.ExitError); ok {
			ws := exiterr.Sys().(syscall.WaitStatus)
			fmt.Println("Command failed with exit code:", ws.ExitStatus())
			exitStatus = int(ws.ExitStatus())
		} else {
			fmt.Fprintln(os.Stderr, "Command failed:", err)
			exitStatus = 1
		}
	}

	syscall.Unmount("/proc", 0)
	syscall.Unmount("/dev/urandom", 0)
	syscall.Unmount("/dev/random", 0)
	syscall.Unmount("/dev/null", 0)

	os.RemoveAll("/dev")
	os.RemoveAll("/proc")

	os.Exit(exitStatus)
}
