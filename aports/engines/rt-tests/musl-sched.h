/*
 * rt-tests on musl (nura-builds, included first through CPPFLAGS=-include): musl's
 * sched_setscheduler, sched_getscheduler, sched_getparam and sched_setparam return ENOSYS on
 * purpose (Linux applies them to a thread, POSIX to the process). glibc passes them to the
 * kernel, and rt-tests relies on that: cyclictest's privilege check and its measuring threads.
 * Here they are the system calls, as with glibc.
 */
#ifndef NURA_MUSL_SCHED_H
#define NURA_MUSL_SCHED_H

#include <sched.h>
#include <unistd.h>
#include <sys/syscall.h>

#ifndef __GLIBC__
static inline int nura_sched_setscheduler(pid_t pid, int policy, const struct sched_param *param)
{
	return syscall(SYS_sched_setscheduler, pid, policy, param);
}

static inline int nura_sched_getscheduler(pid_t pid)
{
	return syscall(SYS_sched_getscheduler, pid);
}

static inline int nura_sched_getparam(pid_t pid, struct sched_param *param)
{
	return syscall(SYS_sched_getparam, pid, param);
}

static inline int nura_sched_setparam(pid_t pid, const struct sched_param *param)
{
	return syscall(SYS_sched_setparam, pid, param);
}

#define sched_setscheduler(pid, policy, param) nura_sched_setscheduler(pid, policy, param)
#define sched_getscheduler(pid) nura_sched_getscheduler(pid)
#define sched_getparam(pid, param) nura_sched_getparam(pid, param)
#define sched_setparam(pid, param) nura_sched_setparam(pid, param)
#endif

#endif
