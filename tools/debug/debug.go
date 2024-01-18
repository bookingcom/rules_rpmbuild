package debug

import (
	"fmt"
	"os"
	"strconv"
)

var debugEnabled = initDebug()

func initDebug() bool {
	val := os.Getenv("DEBUG_RPMBUILD")
	if val == "" {
		return false
	}

	boolValue, err := strconv.ParseBool(val)
	if err != nil {
		return boolValue
	}

	intValue, _ := strconv.ParseInt(val, 10, 64)
	return intValue > 0
}

func DEBUG(args ...interface{}) {
	if !debugEnabled {
		return;
	}

	fmt.Fprintln(os.Stderr, args...);
}
