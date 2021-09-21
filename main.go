package main

import (
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
)

func getMfactForWindow(mfactLine string, window string) (mfact string) {
	mfacts := strings.Split(mfactLine, ";")
	for _, mfactPairLine := range mfacts {
		mfactPair := strings.Split(mfactPairLine, ":")
		if window == mfactPair[0] {
			return mfactPair[1]
		}
	}
	_, err := strconv.Atoi(window)
	if err != nil {
		return ""
	}
	newEntry := mfactLine + ";" + window + ":50"
	_, err = exec.Command(
		"tmux",
		"setenv", "mfact2", newEntry,
	).Output()
	if err != nil {
		panic(err)
	}
	return "50"
}

func updateMfactForWindow(mfactLine string, window string, amount int) (mfact string) {
	ok := false
	finalAmount := ""
	mfacts := strings.Split(mfactLine, ";")
	for i, mfactPairLine := range mfacts {
		mfactPair := strings.Split(mfactPairLine, ":")
		if window == mfactPair[0] {
			mfact, err := strconv.Atoi(mfactPair[1])
			if err != nil {
				return mfactLine
			}
			value := mfact + amount
			if value > 95 || value < 5 {
				return mfactLine
			}
			finalAmount = strconv.Itoa(value)
			mfactPair[1] = finalAmount
			mfacts[i] = mfactPair[0] + ":" + mfactPair[1]
			ok = true
			continue
		}
	}
	result := strings.Join(mfacts, ";")
	if !ok {
		return mfactLine
	}
	_, err := exec.Command(
		"tmux",
		"setenv", "mfact2", result, ";",
		"resize-pane", "-t", ":.0", "-x", finalAmount+"%",
	).Output()
	if err != nil {
		fmt.Println(err.Error())
		return
	}

	return result
}

func main() {
	// exec.Command("tmux", "setenv", "-g", "mfact2", "1:50;2:34").Output()
	params := "#I,#{window_panes},#{mfact2},#{killlast}"
	cmd := exec.Command("tmux", "display-message", "-p", params)
	stdout, err := cmd.Output()
	if err != nil {
		fmt.Println(err.Error())
		return
	}
	result := strings.Split(string(stdout), ",")
	current_window := result[0]
	// window_panes := result[1]
	mfact := result[2]
	// killalllast := result[3]

	if len(os.Args) > 1 {
		amountStr := os.Args[1]
		amount, err := strconv.Atoi(amountStr)
		if err != nil {
			fmt.Println(getMfactForWindow(mfact, current_window))
			return
		}
		updateMfactForWindow(mfact, current_window, amount)
		return
	}
	fmt.Println(getMfactForWindow(mfact, current_window))
}
