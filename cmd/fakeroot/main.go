package main

// based on https://github.com/lure-sh/fakeroot

import (
	"fmt"
	"os"
	"os/exec"
	"syscall"

	"github.com/bookingcom/rules_rpmbuild/tools/debug"
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
	cmd.Env = append(cmd.Env,
		fmt.Sprintf("%s=1", INSIDE_CHROOT),
		"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
	)
	_, epoch := os.LookupEnv("SOURCE_DATE_EPOCH")
	if epoch {
		debug.DEBUG("Propagating SOURCE_DATE_EPOCH:", os.Getenv("SOURCE_DATE_EPOCH"))
		cmd.Env = append(cmd.Env, "SOURCE_DATE_EPOCH=" + os.Getenv("SOURCE_DATE_EPOCH"))
	}
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

	err := cmd.Run()
	if err == nil {
		os.Exit(0)
	}
	if exiterr, ok := err.(*exec.ExitError); ok {
		ws := exiterr.Sys().(syscall.WaitStatus)
		debug.DEBUG("Command failed with exit code:", ws.ExitStatus())
		os.Exit(int(ws.ExitStatus()))
	} else {
		debug.DEBUG("Command failed:", err)
		os.Exit(1)
	}
}

func runInNamespace() {
	syscall.Sethostname([]byte("inside-container"))

	cmd := exec.Command(os.Args[1], os.Args[2:]...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	err := cmd.Run()
	if err == nil {
		os.Exit(0)
	}

	if exiterr, ok := err.(*exec.ExitError); ok {
		ws := exiterr.Sys().(syscall.WaitStatus)
		debug.DEBUG("Command failed with exit code:", ws.ExitStatus())
		os.Exit(int(ws.ExitStatus()))
	} else {
		debug.DEBUG("Command failed:", err)
		os.Exit(1)
	}
}
