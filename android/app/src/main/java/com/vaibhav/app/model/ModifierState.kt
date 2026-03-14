package com.vaibhav.app.model

enum class ModifierState {
    OFF, ON, LOCKED;

    fun next(lastTapTime: Long, now: Long, doubleTapThreshold: Long = 300L): ModifierState {
        return when (this) {
            OFF -> ON
            ON -> if (now - lastTapTime < doubleTapThreshold) LOCKED else OFF
            LOCKED -> OFF
        }
    }
}
