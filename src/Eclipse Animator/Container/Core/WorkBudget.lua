--!nocheck
--// cracked by numan

local require = require(script:FindFirstAncestor("Container").Require)

local State = require("State")
local WorkBudget = {}
const runs = {}
const steps = setmetatable({}, { __mode = "k" })
local watcher

const GRACE = 0.08
const SLICE = 1 / 30
const STALL = 5
const WATCH = 0.25

local function dead(thread)
	return type(thread) == "thread" and coroutine.status(thread) == "dead"
end

local function release(run)
	run.finished = true
	if runs[run.thread] == run then
		runs[run.thread] = nil
	end

	if State.ProjectWorkStep == run.step then
		State.ProjectWorkStep = nil
	end

	if run.holding and State.LoadingProject == true and State.ProjectLoadThread == run.thread then
		State.LoadingProject, State.ProjectLoadThread = run.loading, run.owner
	end

	run.holding = false
end

local function watch()
	if watcher then
		return
	end

	watcher = true
	task.spawn(function()
		repeat
			task.wait(WATCH)
			WorkBudget.settle()
		until next(runs) == nil and not State.LoadingProject
		watcher = nil
	end)
end

function WorkBudget.settle()
	for thread, run in runs do
		if run.finished or dead(thread) then
			release(run)
		end
	end

	const step = State.ProjectWorkStep
	const owner = step and steps[step]
	if owner and (owner.finished or dead(owner.thread)) then
		State.ProjectWorkStep = nil
	end

	if State.LoadingProject and dead(State.ProjectLoadThread) then
		const live = State.ProjectWorkStep and steps[State.ProjectWorkStep]
		if not live then
			State.ProjectWorkStep = nil
		end

		State.LoadingProject, State.ProjectLoadThread = nil, nil
	end

	if State.LoadingProject then
		watch()
	end
end

function WorkBudget.busy()
	WorkBudget.settle()
	const current = coroutine.running()
	const now = os.clock()
	for thread, run in runs do
		if thread ~= current and now - run.progressed < STALL then
			return true
		end
	end

	return false
end

function WorkBudget.wait(timeout, stop)
	const deadline = os.clock() + timeout
	while
		coroutine.isyieldable()
		and os.clock() < deadline
		and not (stop and stop())
		and WorkBudget.busy()
	do
		task.wait()
	end

	return not WorkBudget.busy()
end

function WorkBudget.run(callback, ...)
	if not coroutine.isyieldable() then
		return callback(...)
	end

	WorkBudget.settle()
	const thread = coroutine.running()
	const existing = runs[thread]
	if existing then
		if not State.ProjectWorkStep then
			State.ProjectWorkStep = existing.step
		end

		return callback(...)
	end

	if State.ProjectWorkStep then
		return callback(...)
	end

	const run = { thread = thread, started = os.clock(), holding = false }
	run.progressed = run.started
	local slice = run.started
	local function step()
		if coroutine.running() ~= thread then
			return
		end

		const now = os.clock()
		run.progressed = now
		if now - run.started < GRACE or now - slice < SLICE or not coroutine.isyieldable() then
			return
		end

		const claim = not State.LoadingProject
		if claim then
			run.loading, run.owner = State.LoadingProject, State.ProjectLoadThread
			State.LoadingProject, State.ProjectLoadThread = true, thread
			run.holding = true
		end

		task.wait()
		if claim and run.holding then
			run.holding = false
			if State.LoadingProject == true and State.ProjectLoadThread == thread then
				State.LoadingProject, State.ProjectLoadThread = run.loading, run.owner
			end
		end

		slice = os.clock()
		run.progressed = slice
	end

	run.step = step
	steps[step] = run
	runs[thread] = run
	State.ProjectWorkStep = step
	watch()
	const result = table.pack(pcall(callback, ...))
	release(run)
	if not result[1] then
		error(result[2], 0)
	end

	return table.unpack(result, 2, result.n)
end

return WorkBudget
