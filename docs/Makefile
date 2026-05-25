
dev: clean open watch

harnessing-problem.pdf: harnessing-problem.tex
	latexmk harnessing-problem.tex

open: harnessing-problem.pdf
	open harnessing-problem.pdf

watch: harnessing-problem.tex
	latexmk -pvc harnessing-problem.tex

clean:
	latexmk -C
