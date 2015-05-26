
FILES = mongrel2.nim

default: development

debug: ${FILES}
	nim --assertions:on --nimcache:.cache c ${FILES}

development: ${FILES}
	# can use gdb with this...
	nim -r --debugInfo --linedir:on --define:testing --nimcache:.cache c ${FILES}

debugger: ${FILES}
	nim --debugger:on --nimcache:.cache c ${FILES}

release: ${FILES}
	nim -d:release --opt:speed --nimcache:.cache c ${FILES}

docs:
	nim doc ${FILES}
	#nim buildIndex ${FILES}

clean:
	cat .hgignore | xargs rm -rf

