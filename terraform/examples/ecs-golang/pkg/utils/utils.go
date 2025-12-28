package utils

import "time"

func GetLocalTimestamp(t time.Time) string {
	return t.Format("2006-01-02T15:04:05.000Z")
}

func GetLocalTimestampNow() string {
	t := time.Now()
	return GetLocalTimestamp(t)
}
