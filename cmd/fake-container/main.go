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
	cmd.Env = append(cmd.Env, fmt.Sprintf("%s=1", INSIDE_CHROOT))
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
	if uid != 0 {
		cmd.SysProcAttr.UidMappings = append(cmd.SysProcAttr.UidMappings, syscall.SysProcIDMap{
			ContainerID: 0,
			HostID:      uid,
			Size:        1,
		})

		cmd.SysProcAttr.GidMappings = append(cmd.SysProcAttr.GidMappings, syscall.SysProcIDMap{
			ContainerID: 0,
			HostID:      uid,
			Size:        1,
		})
	}

	cmd.Run()
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
}

func runInNamespace() {
	syscall.Sethostname([]byte("inside-container"))

	chroot := os.Args[1]

	mountProc(chroot)

	os.MkdirAll(chroot + "/dev", 0777)
	mountDevFile(chroot, "/dev/urandom")
	mountDevFile(chroot, "/dev/random")

	err := syscall.Chroot(chroot)
	if err != nil {
		fmt.Println("Failed to chroot:", err)
		os.Exit(1)
	}

	err = syscall.Chdir("/") // set the working directory inside container
	if err != nil {
		fmt.Println("Failed to chdir:", err)
		os.Exit(1)
	}

	cmd := exec.Command(os.Args[2], os.Args[3:]...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	cmd.Run()

	syscall.Unmount("/proc", 0)
	syscall.Unmount("/dev/urandom", 0)
	syscall.Unmount("/dev/random", 0)

	os.RemoveAll("/dev")
	os.RemoveAll("/proc")
}
