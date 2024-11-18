VERSION = "0.4.4"



local micro = import("micro")
local config = import("micro/config")
local shell = import("micro/shell")
local buffer = import("micro/buffer")
local util = import("micro/util")
local utf8 = import("unicode/utf8")



function init()
    config.MakeCommand("synctex-forward", synctexForward, config.NoComplete)
    linter.makeLinter("latex", "tex", "pdflatex", {"-interaction=nonstopmode", "-draftmode", "-file-line-error", "%f"}, "%f:%l:%m", {"linux"}, true, false)
    config.AddRuntimeFile("latex-plugin-help", config.RTHelp, "help/latex-plugin.md")

	-- F5 to look at bib entries
	config.MakeCommand("bibentry", bibentryCommand, config.NoComplete)
	config.TryBindKey("F5", "command:bibentry", true)
end

function bibentryCommand(bp)
	if bp.Buf:FileType() == "tex" then
		local fileName = bp.Buf:GetName()
		local truncFileName = fileName:sub(1, -5)
		local bibFileName = truncFileName .. ".bib"

		local cmd = string.format("bash -c \"grep '^@' %s | awk -F'[{,]' '{print $2}' | sort | fzf --layout=reverse\"", bibFileName)

		local out, err = shell.RunInteractiveShell(cmd, false, true)
		local out2 = out:gsub('\n','')
		bp.Buf:Insert(-bp.Cursor.Loc, out2) -- got this from  the jlabbrev plugin
	end
end


function onBufferOpen(buf)
	if buf:FileType() == "tex" then
		local fileName = buf:GetName()
		syncFileName = fileName .. ".synctex.from-zathura-to-micro.fifo"
		local shellFifoRead = "while true; do read -r linenumber < " .. syncFileName:gsub(" ", "\\%0") .. " && echo $linenumber; done"

		shell.ExecCommand("mkfifo", syncFileName)
		jobFifoRead = shell.JobStart(shellFifoRead, synctexBackward, nil, dummyFunc)
		isSynctexBackwardDaemonRunning = true
	end
end



function preSave(bp)
	if bp.Buf:FileType() == "tex" then
		isBufModified = bp.Buf:Modified()
	end
end



function onSave(bp)
	if bp.Buf:FileType() == "tex" then
		if isBufModified == true then
			compile(bp)
		end
		synctexForward(bp)
	end
end



function synctexForward(bp)
	local fileName = bp.Buf:GetName():gsub(" ", "\\%0")
	local pdfFileName = fileName:sub(1, -5) .. ".pdf"
	local cursor = bp.Buf:GetActiveCursor()
	local zathuraArgPos = string.format(" --synctex-forward=%i:%i:%s", cursor.Y+1, cursor.X, fileName)
	local zathuraArgSynctexBackward = " --synctex-editor-command=\"bash -c \'echo %{line} > " .. syncFileName .. "\'\""
	local zathuraArgFile = " " .. pdfFileName;

	shell.JobStart("zathura " .. zathuraArgSynctexBackward .. zathuraArgPos .. zathuraArgFile, nil, nil, dummyFunc)
end



function synctexBackward(pos)
	micro.CurPane():GotoCmd({pos:sub(1, -2)})
end



function compile(bp)
	local fileName = bp.Buf:GetName():match("[^/]+$")
	local auxFileName = fileName:sub(1, -5) .. ".aux"

	shell.ExecCommand("pdflatex", "-interaction=nonstopmode", "-draftmode", fileName)
	shell.ExecCommand("bibtex", auxFileName)
	shell.ExecCommand("pdflatex", "-interaction=nonstopmode", "-draftmode", fileName)
	-- For an unknown reason synctex-related files keeps deleted right after
	-- finishing ExecCommand. It easy to notice while using RunInteractiveShell:
	-- there are synctex-related files after pdflatex ends their job and files
	-- disappear after returning to micro by pressing enter. Because of this
	-- there is JobStart function that does not exhibit such behaviour
	shell.JobStart("pdflatex -interaction=nonstopmode -synctex=15 " .. fileName, nil, nil, dummyFunc)
end



function preQuit(bp)
	if isSynctexBackwardDaemonRunning == true then
		shell.ExecCommand("rm", syncFileName)
		shell.JobStop(jobFifoRead)
	end

	if bp.Buf:FileType() == "tex" then
		local fileName = bp.Buf:GetName()
		local truncFileName = fileName:sub(1, -5)
		local auxFileName = truncFileName .. ".aux"
		local logFileName = truncFileName .. ".log"
		local outFileName = truncFileName .. ".out"
		-- local bblFileName = truncFileName .. ".bbl"
		local blgFileName = truncFileName .. ".blg"

		shell.JobStop(jobFifoRead)
		shell.ExecCommand("rm", auxFileName)
		shell.ExecCommand("rm", logFileName)
		shell.ExecCommand("rm", outFileName)
		-- shell.ExecCommand("rm", bblFileName)
		shell.ExecCommand("rm", blgFileName)
	end
end



function dummyFunc()

end
