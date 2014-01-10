/*****************************************************************************

Copyright (c) 1994, 2013, Oracle and/or its affiliates. All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; version 2 of the License.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc.,
51 Franklin Street, Suite 500, Boston, MA 02110-1335 USA

*****************************************************************************/

/*****************************************************************//**
@file ut/ut0dbg.cc
Debug utilities for Innobase.

Created 1/30/1994 Heikki Tuuri
**********************************************************************/

#include "ha_prototypes.h"

#include "ut0dbg.h"

/*************************************************************//**
Report a failed assertion. */

void
ut_dbg_assertion_failed(
/*====================*/
	const char* expr,	/*!< in: the failed assertion (optional) */
	const char* file,	/*!< in: source file containing the assertion */
	ulint line)		/*!< in: line number of the assertion */
{
	ut_print_timestamp(stderr);
#ifdef UNIV_HOTBACKUP
	fprintf(stderr, "  InnoDB: Assertion failure in file %s line %lu\n",
		file, line);
#else /* UNIV_HOTBACKUP */
	fprintf(stderr,
		"  InnoDB: Assertion failure in thread %lu"
		" in file %s line %lu\n",
		os_thread_pf(os_thread_get_curr_id()),
		innobase_basename(file), line);
#endif /* UNIV_HOTBACKUP */
	if (expr) {
		fprintf(stderr,
			"InnoDB: Failing assertion: %s\n", expr);
	}

	fputs("InnoDB: We intentionally generate a memory trap.\n"
	      "InnoDB: Submit a detailed bug report"
	      " to http://bugs.mysql.com.\n"
	      "InnoDB: If you get repeated assertion failures"
	      " or crashes, even\n"
	      "InnoDB: immediately after the mysqld startup, there may be\n"
	      "InnoDB: corruption in the InnoDB tablespace. Please refer to\n"
	      "InnoDB: "REFMAN"forcing-innodb-recovery.html\n"
	      "InnoDB: about forcing recovery.\n", stderr);

	fflush(stderr);
	fflush(stdout);
	abort();
}

#ifdef UNIV_COMPILE_TEST_FUNCS

#include <sys/types.h>
#include <sys/time.h>
#ifdef HAVE_SYS_RESOURCE_H
# include <sys/resource.h>
#endif

#include <unistd.h>

#ifndef timersub
#define timersub(a, b, r)						\
	do {								\
		(r)->tv_sec = (a)->tv_sec - (b)->tv_sec;		\
		(r)->tv_usec = (a)->tv_usec - (b)->tv_usec;		\
		if ((r)->tv_usec < 0) {					\
			(r)->tv_sec--;					\
			(r)->tv_usec += 1000000;			\
		}							\
	} while (0)
#endif /* timersub */

/*******************************************************************//**
Resets a speedo (records the current time in it). */

void
speedo_reset(
/*=========*/
	speedo_t*	speedo)	/*!< out: speedo */
{
	gettimeofday(&speedo->tv, NULL);

	getrusage(RUSAGE_SELF, &speedo->ru);
}

/*******************************************************************//**
Shows the time elapsed and usage statistics since the last reset of a
speedo. */

void
speedo_show(
/*========*/
	const speedo_t*	speedo)	/*!< in: speedo */
{
	struct rusage	ru_now;
	struct timeval	tv_now;
	struct timeval	tv_diff;

	getrusage(RUSAGE_SELF, &ru_now);

	gettimeofday(&tv_now, NULL);

#define PRINT_TIMEVAL(prefix, tvp)		\
	fprintf(stderr, "%s% 5ld.%06ld sec\n",	\
		prefix, (tvp)->tv_sec, (tvp)->tv_usec)

	timersub(&tv_now, &speedo->tv, &tv_diff);
	PRINT_TIMEVAL("real", &tv_diff);

	timersub(&ru_now.ru_utime, &speedo->ru.ru_utime, &tv_diff);
	PRINT_TIMEVAL("user", &tv_diff);

	timersub(&ru_now.ru_stime, &speedo->ru.ru_stime, &tv_diff);
	PRINT_TIMEVAL("sys ", &tv_diff);
}

#endif /* UNIV_COMPILE_TEST_FUNCS */