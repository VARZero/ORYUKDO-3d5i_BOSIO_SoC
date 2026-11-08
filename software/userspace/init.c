#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

int main(void) {
    if (mount("devtmpfs", "/dev", "devtmpfs", 0, "") < 0 && errno != EBUSY) perror("mount /dev");
    if (mount("proc", "/proc", "proc", 0, "") < 0) perror("mount /proc");
    if (mount("sysfs", "/sys", "sysfs", 0, "") < 0) perror("mount /sys");
    setenv("PATH", "/bin", 1);
    setenv("HOME", "/", 1);
    setenv("TERM", "vt100", 1);
    setenv("PS1", "oryukdo# ", 1);
    for (;;) {
        pid_t shell = fork();
        if (shell == 0) {
            if (setsid() < 0) _exit(110);
            int tty = open("/dev/hvc0", O_RDWR);
            if (tty < 0 || ioctl(tty, TIOCSCTTY, 0) < 0) { perror("hvc0"); _exit(111); }
            for (int i = 0; i < 3; i++) if (dup2(tty, i) < 0) _exit(112);
            if (tty > 2) close(tty);
            puts("ORYUKDO BusyBox serial console");
            fflush(stdout);
            execl("/bin/sh", "sh", "-i", (char *)0);
            perror("exec sh"); _exit(127);
        }
        if (shell < 0) { perror("fork"); sleep(1); continue; }
        for (;;) {
            pid_t child = wait(NULL);
            if (child == shell || (child < 0 && errno != EINTR)) break;
        }
        sleep(1);
    }
}
