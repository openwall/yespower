# Copyright 2013-2018 Alexander Peslyak
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

CC = gcc
LD = $(CC)
RM = rm -f
OMPFLAGS = -fopenmp
CFLAGS = -Wall -O2 -fomit-frame-pointer
#CFLAGS = -Wall -msse -O2 -fomit-frame-pointer
#CFLAGS = -Wall -msse2 -O2 -fomit-frame-pointer
#CFLAGS = -Wall -O2 -march=native -fomit-frame-pointer
# -lrt is for benchmark's use of clock_gettime()
LDFLAGS = -s -lrt

PROJ = tests benchmark
OBJS_CORE = yespower-opt.o
OBJS_COMMON = sha256.o
OBJS_TESTS = $(OBJS_CORE) $(OBJS_COMMON) tests.o
OBJS_BENCHMARK = $(OBJS_CORE) $(OBJS_COMMON) benchmark.o
OBJS_RM = yespower-*.o

all: $(PROJ)

check: tests
	@echo 'Running tests'
	@time ./tests | tee TESTS-OUT
	@diff -U0 TESTS-OK TESTS-OUT && echo PASSED || echo FAILED

ref:
	$(MAKE) $(PROJ) OBJS_CORE=yespower-ref.o

check-ref:
	$(MAKE) check OBJS_CORE=yespower-ref.o

tests: $(OBJS_TESTS)
	$(LD) $(LDFLAGS) $(OBJS_TESTS) -o $@

benchmark: $(OBJS_BENCHMARK)
	$(LD) $(LDFLAGS) $(OMPFLAGS) $(OBJS_BENCHMARK) -o $@

benchmark.o: benchmark.c
	$(CC) -c $(CFLAGS) $(OMPFLAGS) $*.c

.c.o:
	$(CC) -c $(CFLAGS) $*.c

yespower-ref.o: yespower.h
yespower-opt.o: yespower-platform.c yespower.h
tests.o: yespower.h
benchmark.o: yespower.h

clean:
	$(RM) $(PROJ)
	$(RM) $(OBJS_TESTS) $(OBJS_BENCHMARK)
	$(RM) $(OBJS_RM)
	$(RM) TESTS-OUT
