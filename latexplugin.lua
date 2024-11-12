VERSION = "0.4.3"


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
end

 

function testHandler(text)
	micro.InfoBar():Message(text)
end


function onBufferOpen(buf)
	isTex = (buf:FileType() == "tex")
	if isTex then
		local fileName = buf:GetName()
		-- local truncFileName =fileName:sub(1, -5)
		local syncFileName = fileName .. ".synctex.from-zathura-to-micro"
		--local scriptFifoWriteFileName = fileName .. ".fifo-writer.sh"
		--local scriptFifoWrite = "echo \"$@\" > " .. syncFileName:gsub(" ", "\\%0")
		local shellFifoRead = "while true; do read -r linenumber < " .. syncFileName:gsub(" ", "\\%0") .. " && echo $linenumber; done"
		
		shell.ExecCommand("mkfifo", syncFileName)
		--local f = io.open(scriptFifoWriteFileName, "w")
		--f:write(scriptFifoWrite)
		--f:close()
		--shell.ExecCommand("chmod", "755", scriptFifoWriteFileName)

		jobFifoRead = shell.JobStart(shellFifoRead, synctexBackward, nil, dummyFunc)

		
	end
end


function preSave(bp)
	if isTex then
		isBufferModified = bp.Buf:Modified()
	end
end


function onSave(bp)
	if isTex then
--		local isError = lint(bp)
--		if not isError then
--			if isBufferModified then
--				compile(bp)
--			end
--			synctexForward(bp)

		-- try to compile anyway
		compile(bp)
		synctexForward(bp)
	end
end


function synctexForward(bp)
	local fileName = bp.Buf:GetName():gsub(" ", "\\%0")
	-- local truncFileName = fileName:sub(1, -5)
	local syncFileName = fileName .. ".synctex.from-zathura-to-micro"
	--local scriptFifoWriteFileName = fileName .. ".fifo-writer.sh"
	local pdfFileName = fileName:sub(1, -5) .. ".pdf"

	local cursor = bp.Buf:GetActiveCursor()
	local zathuraArgPos = string.format(" --synctex-forward=%i:%i:%s", cursor.Y+1, cursor.X, fileName)
	-- local zathuraArgSynctexBackward = " --synctex-editor-command=\'" .. scriptFifoWriteFileName .." %{line}\'"
	local zathuraArgSynctexBackward = " --synctex-editor-command=\"bash -c \'echo %{line} > " .. syncFileName .. " %{line}\'\""
	local zathuraArgFile = " " .. pdfFileName;

	shell.JobStart("zathura " .. zathuraArgSynctexBackward .. zathuraArgPos .. zathuraArgFile, nil, nil, dummyFunc)
end


function synctexBackward(pos)
	local bp = micro.CurPane()
	micro.InfoBar():Message("#"..pos.."#")
	bp:GotoCmd({pos:sub(1, -2)})
end


function lint(bp)
	local fileName = bp.Buf:GetName()
	-- local truncFileName = fileName:sub(1, -5)

	-- syncex=15 added because otherwise pdflatex cleans up synctex files as well
	local output = shell.ExecCommand("pdflatex", "-interaction=nonstopmode", "-draftmode", "-file-line-error", fileName)
	local error = output:match("[^\n/]+:%w+:[^\n]+")
	if error then
		micro.InfoBar():Message(error)
		local errorPos = error:match(":%w+:"):sub(2, -2)
		-- do not jump to the error (to be fixed)
		-- micro.CurPane():GotoCmd({errorPos})
		return true
	else
		return false
	end
end


function compile(bp)
	local fileName = bp.Buf:GetName()

	--shell.ExecCommand("pdflatex", "-interaction=nonstopmode", "-draftmode", fileName)
	shell.ExecCommand("bibtex", fileName:sub(1, -5):match("[^/]+$"))
	shell.ExecCommand("pdflatex", "-interaction=nonstopmode", "-draftmode", fileName)
	shell.ExecCommand("pdflatex", "-synctex=15", "-interaction=nonstopmode", fileName)
end


function preQuit(bp)
	if isTex then
		local fileName = bp.Buf:GetName()
		-- local truncFileName = fileName:sub(1, -5)
		local syncFileName = fileName .. ".synctex.from-zathura-to-micro"
		local scriptFifoWriteFileName = fileName .. ".fifo-writer.sh"

		shell.JobStop(jobFifoRead)
		shell.ExecCommand("rm", syncFileName)
		shell.ExecCommand("rm", scriptFifoWriteFileName)
	end
end


function dummyFunc()

end
