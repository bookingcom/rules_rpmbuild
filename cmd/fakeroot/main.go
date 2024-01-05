package main

// based on https://github.com/lure-sh/fakeroot

import (
	"fmt"
	"os"
	"os/exec"
	"syscall"
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
	if len(os.Args) < 2 {
		fmt.Println("Usage: fakeroot <command> [arguments...]")
		os.Exit(1)
	}

	cmd := exec.Command("/proc/self/exe", os.Args[1:]...)
	cmd.Env = append(cmd.Env, fmt.Sprintf("%s=1", INSIDE_CHROOT))
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.SysProcAttr = &syscall.SysProcAttr{
		Cloneflags:
			syscall.CLONE_NEWUSER,	// isolated user namespace (prevents access to host users)
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

func runInNamespace() {
	syscall.Sethostname([]byte("inside-container"))

	cmd := exec.Command(os.Args[1], os.Args[2:]...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	cmd.Run()
}
