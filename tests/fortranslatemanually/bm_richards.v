module main

// To compile with globals, use: v -enable-globals .
import strings
import div72.vexc
import math

// @line: bm_richards.py:43:0
@[heap]
pub struct Packet {
pub:
    datum i64
    data []i64
pub mut:
    link ?Packet
    ident i64
    kind i64
}
// @line: bm_richards.py:68:0

pub interface TaskRec {
}

// @line: bm_richards.py:68:0
@[heap]
pub struct TaskRec_Impl {
}
// @line: bm_richards.py:72:0
@[heap]
pub struct DeviceTaskRec {
pub:
    TaskRec_Impl
    pending ?Packet
}
// @line: bm_richards.py:78:0
@[heap]
pub struct IdleTaskRec {
pub:
    TaskRec_Impl
    control i64
    count i64
}
// @line: bm_richards.py:85:0
@[heap]
pub struct HandlerTaskRec {
pub:
    TaskRec_Impl
pub mut:
    work_in ?Packet
    device_in ?Packet
}
// @line: bm_richards.py:100:0
@[heap]
pub struct WorkerTaskRec {
pub:
    TaskRec_Impl
    destination i64
    count i64
}
// @line: bm_richards.py:108:0

pub interface TaskState {
    packet_pending bool
    task_waiting bool
    task_holding bool
    packet_pending() TaskState
    waiting() TaskState
    running() TaskState
    waiting_with_packet() TaskState
    is_packet_pending() bool
    is_task_waiting() bool
    is_task_holding() bool
    is_task_holding_or_waiting() bool
    is_waiting_with_packet() bool
}

// @line: bm_richards.py:108:0
@[heap]
pub struct TaskState_Impl {
pub mut:
    packet_pending bool
    task_waiting bool
    task_holding bool
}
// @line: bm_richards.py:171:0
@[heap]
pub struct TaskWorkArea {
pub:
    task_tab []?Task
    task_list ?Task
    hold_count i64
    qpkt_count i64
}
// @line: bm_richards.py:185:0

pub interface Task {
    TaskState_Impl
    link Any
    ident i64
    priority i64
    input ?Packet
    packet_pending bool
    task_waiting bool
    task_holding bool
    handle TaskRec
    py_fn(pkt ?Packet, r TaskRec) ?Task
    add_packet(p &Packet, old Task) Task
    run_task() ?Task
    wait_task() Task
    hold() ?Task
    release(i i64) Task
    qpkt(pkt &Packet) Task
    findtcb(id i64) Task
}

// @line: bm_richards.py:185:0
@[heap]
pub struct Task_Impl {
pub:
    TaskState_Impl
pub mut:
    link Any
    ident i64
    priority i64
    input ?Packet
    packet_pending bool
    task_waiting bool
    task_holding bool
    handle TaskRec
}
// @line: bm_richards.py:264:0
@[heap]
pub struct DeviceTask {
pub:
    Task_Impl
}
// @line: bm_richards.py:286:0
@[heap]
pub struct HandlerTask {
pub:
    Task_Impl
}
// @line: bm_richards.py:319:0
@[heap]
pub struct IdleTask {
pub:
    Task_Impl
}
// @line: bm_richards.py:344:0
@[heap]
pub struct WorkTask {
pub:
    Task_Impl
}
// @line: bm_richards.py:390:0
@[heap]
pub struct Richards {
}

__global i_idle Any
__global i_work Any
__global i_handlera Any
__global i_handlerb Any
__global i_deva Any
__global i_devb Any
__global k_dev Any
__global k_work Any
__global bufsize Any
__global bufsize_range Any
__global tracing Any
__global layout int
__global tasktabsize Any
__global task_work_area Any
__global a i64

pub const i_idle = 1
pub const i_work = 2
pub const i_handlera = 3
pub const i_handlerb = 4
pub const i_deva = 5
pub const i_devb = 6
pub const k_dev = 1000
pub const k_work = 1001
pub const bufsize = 4
pub const packet_new_packet_annotations = { 'l': '?Packet', 'i': 'i64', 'k': 'i64' }
pub const packet_append_to_annotations = { 'lst': '?Packet', 'return': '&Packet' }
pub const handler_task_rec_work_in_add_annotations = { 'p': '&Packet', 'return': '&Packet' }
pub const handler_task_rec_device_in_add_annotations = { 'p': '&Packet', 'return': '&Packet' }
pub const task_state_impl_packet_pending_annotations = { 'return': 'TaskState' }
pub const task_state_impl_waiting_annotations = { 'return': 'TaskState' }
pub const task_state_impl_running_annotations = { 'return': 'TaskState' }
pub const task_state_impl_waiting_with_packet_annotations = { 'return': 'TaskState' }
pub const task_state_impl_is_packet_pending_annotations = { 'return': 'bool' }
pub const task_state_impl_is_task_waiting_annotations = { 'return': 'bool' }
pub const task_state_impl_is_task_holding_annotations = { 'return': 'bool' }
pub const task_state_impl_is_task_holding_or_waiting_annotations = { 'return': 'bool' }
pub const task_state_impl_is_waiting_with_packet_annotations = { 'return': 'bool' }
pub const trace_annotations = { 'a': 'Any' }
pub const tasktabsize = 10
pub const task_impl_new_task_impl_annotations = { 'i': 'i64', 'p': 'i64', 'w': '?Packet', 'initial_state': 'TaskState', 'r': 'TaskRec' }
pub const task_impl_py_fn_annotations = { 'pkt': '?Packet', 'r': 'TaskRec', 'return': '?Task' }
pub const task_impl_add_packet_annotations = { 'p': '&Packet', 'old': 'Task', 'return': 'Task' }
pub const task_impl_run_task_annotations = { 'return': '?Task' }
pub const task_impl_wait_task_annotations = { 'return': 'Task' }
pub const task_impl_hold_annotations = { 'return': '?Task' }
pub const task_impl_release_annotations = { 'i': 'i64', 'return': 'Task' }
pub const task_impl_qpkt_annotations = { 'pkt': '&Packet', 'return': 'Task' }
pub const task_impl_findtcb_annotations = { 'id': 'i64', 'return': 'Task' }
pub const device_task_new_device_task_annotations = { 'i': 'i64', 'p': 'i64', 'w': '?Packet', 's': 'TaskState', 'r': '&DeviceTaskRec' }
pub const device_task_py_fn_annotations = { 'pkt': '?Packet', 'r': 'TaskRec', 'return': '?Task' }
pub const handler_task_new_handler_task_annotations = { 'i': 'i64', 'p': 'i64', 'w': '?Packet', 's': 'TaskState', 'r': '&HandlerTaskRec' }
pub const handler_task_py_fn_annotations = { 'pkt': '?Packet', 'r': 'TaskRec', 'return': '?Task' }
pub const idle_task_new_idle_task_annotations = { 'i': 'i64', 'p': 'i64', 'w': 'i64', 's': 'TaskState', 'r': '&IdleTaskRec' }
pub const idle_task_py_fn_annotations = { 'pkt': '?Packet', 'r': 'TaskRec', 'return': '?Task' }
pub const work_task_new_work_task_annotations = { 'i': 'i64', 'p': 'i64', 'w': '?Packet', 's': 'TaskState', 'r': '&WorkerTaskRec' }
pub const work_task_py_fn_annotations = { 'pkt': '?Packet', 'r': 'TaskRec', 'return': '?Task' }
pub const richards_run_annotations = { 'iterations': 'i64', 'return': 'bool' }

// @line: bm_richards.py:45:4
pub fn new_packet(l ?Packet, i i64, k i64) &Packet {
    mut self := &Packet{}
    self.link = l
    self.ident = i
    self.kind = k
    self.datum = 0
    self.data = []int{len: bufsize, init: 0}
    return &self
}
// @line: bm_richards.py:52:4
pub fn (mut self Packet) append_to(lst ?Packet) &Packet {
    self.link = Any(NoneType{})
    mut p := ?i64(none)
    mut next := ?int(none)
    if lst == none {
        return self
    } else {
        p = ?i64(lst)
        next = ?int(p.link)
        for next != none {
            p = ?i64(next)
            next = ?int(p.link)
        }
        p.link = self
        return lst
    }
}
// @line: bm_richards.py:74:4
pub fn new_device_task_rec() &DeviceTaskRec {
    mut self := &DeviceTaskRec{}
    self.pending = none
    return &self
}
// @line: bm_richards.py:80:4
pub fn new_idle_task_rec() &IdleTaskRec {
    mut self := &IdleTaskRec{}
    self.control = 1
    self.count = 10000
    return &self
}
// @line: bm_richards.py:87:4
pub fn new_handler_task_rec() &HandlerTaskRec {
    mut self := &HandlerTaskRec{}
    self.work_in = none
    self.device_in = none
    return &self
}
// @line: bm_richards.py:91:4
pub fn (mut self HandlerTaskRec) work_in_add(p &Packet) &Packet {
    self.work_in = p.append_to(self.work_in)
    return self.work_in
}
// @line: bm_richards.py:95:4
pub fn (mut self HandlerTaskRec) device_in_add(p &Packet) &Packet {
    self.device_in = p.append_to(self.device_in)
    return self.device_in
}
// @line: bm_richards.py:102:4
pub fn new_worker_task_rec() &WorkerTaskRec {
    mut self := &WorkerTaskRec{}
    self.destination = i_handlera
    self.count = 0
    return &self
}
// @line: bm_richards.py:110:4
pub fn new_task_state_impl() &TaskState_Impl {
    mut self := &TaskState_Impl{}
    self.packet_pending = true
    self.task_waiting = false
    self.task_holding = false
    return &self
}
// @line: bm_richards.py:115:4
pub fn (mut self TaskState_Impl) packet_pending() TaskState {
    self.packet_pending = true
    self.task_waiting = false
    self.task_holding = false
    return self
}
// @line: bm_richards.py:121:4
pub fn (mut self TaskState_Impl) waiting() TaskState {
    self.packet_pending = false
    self.task_waiting = true
    self.task_holding = false
    return self
}
// @line: bm_richards.py:127:4
pub fn (mut self TaskState_Impl) running() TaskState {
    self.packet_pending = false
    self.task_waiting = false
    self.task_holding = false
    return self
}
// @line: bm_richards.py:133:4
pub fn (mut self TaskState_Impl) waiting_with_packet() TaskState {
    self.packet_pending = true
    self.task_waiting = true
    self.task_holding = false
    return self
}
// @line: bm_richards.py:139:4
pub fn (self TaskState_Impl) is_packet_pending() bool {
    return self.packet_pending
}
// @line: bm_richards.py:142:4
pub fn (self TaskState_Impl) is_task_waiting() bool {
    return self.task_waiting
}
// @line: bm_richards.py:145:4
pub fn (self TaskState_Impl) is_task_holding() bool {
    return self.task_holding
}
// @line: bm_richards.py:148:4
pub fn (self TaskState_Impl) is_task_holding_or_waiting() bool {
    return if py_bool(self.task_holding) { self.task_holding } else { Any(if !py_bool(self.packet_pending) { self.task_waiting } else { Any(!py_bool(self.packet_pending)) }) }
}
// @line: bm_richards.py:151:4
pub fn (self TaskState_Impl) is_waiting_with_packet() bool {
    return if py_bool(self.packet_pending) { if py_bool(self.task_waiting) { Any(!py_bool(self.task_holding)) } else { self.task_waiting } } else { self.packet_pending }
}
// @line: bm_richards.py:159:0
pub fn trace(a Any) {
    //##LLM@@ Python 'global' or 'nonlocal' scope modification detected. V heavily discourages global state and has strict mutability rules for closures. Please refactor state management, possibly by passing mutable parameters (mut) explicitly.
    // global layout
    layout -= 1
    mut layout := ?int(none)
    if layout <= 0 {
        println('')
        layout = ?int(50)
    }
    print('${a}')
}
// @line: bm_richards.py:173:4
pub fn new_task_work_area() &TaskWorkArea {
    mut self := &TaskWorkArea{}
    self.task_tab = []?Task{len: tasktabsize, init: none}
    self.task_list = none
    self.hold_count = 0
    self.qpkt_count = 0
    return &self
}
// @line: bm_richards.py:187:4
pub fn new_task_impl(i i64, p i64, w ?Packet, initial_state TaskState, r TaskRec) &Task_Impl {
    mut self := &Task_Impl{}
    self.link = task_work_area.task_list
    self.ident = i
    self.priority = p
    self.input = w
    self.packet_pending = initial_state.is_packet_pending()
    self.task_waiting = initial_state.is_task_waiting()
    self.task_holding = initial_state.is_task_holding()
    self.handle = r
    task_work_area.task_list = self
    task_work_area.task_tab[i] = self
    return &self
}
// @line: bm_richards.py:203:4
pub fn (self Task_Impl) py_fn(pkt ?Packet, r TaskRec) ?Task {
    return none
}
// @line: bm_richards.py:206:4
pub fn (mut self Task_Impl) add_packet(p &Packet, old Task) Task {
    if self.input == none {
        self.input = p
        self.packet_pending = true
        if self.priority > old.priority {
            return self
        }
    } else {
        p.append_to(self.input)
    }
    return old
}
// @line: bm_richards.py:216:4
pub fn (mut self Task_Impl) run_task() ?Task {
    mut msg := ?Packet(none)
    if py_bool(self.is_waiting_with_packet()) {
        msg = ?Packet(self.input)
        assert msg != none
        self.input = msg.link
        if self.input == none {
            self.running()
        } else {
            self.packet_pending()
        }
    } else {
        msg = none
    }
    return self.py_fn(msg, self.handle)
}
// @line: bm_richards.py:230:4
pub fn (mut self Task_Impl) wait_task() Task {
    self.task_waiting = true
    return self
}
// @line: bm_richards.py:234:4
pub fn (mut self Task_Impl) hold() ?Task {
    task_work_area.hold_count += 1
    self.task_holding = true
    return self.link
}
// @line: bm_richards.py:239:4
pub fn (self Task_Impl) release(i i64) Task {
    mut t := self.findtcb(i)
    t.task_holding = false
    if t.priority > self.priority {
        return t
    } else {
        return self
    }
}
// @line: bm_richards.py:247:4
pub fn (self Task_Impl) qpkt(mut pkt &Packet) Task {
    mut t := self.findtcb(pkt.ident)
    task_work_area.qpkt_count += 1
    pkt.link = Any(NoneType{})
    pkt.ident = self.ident
    return t.add_packet(pkt, self)
}
// @line: bm_richards.py:254:4
pub fn (self Task_Impl) findtcb(id i64) Task {
    mut t := task_work_area.task_tab[id]
    if t == none {
        vexc.raise('Exception', `Bad task id ${id}`)
    }
    return t
}
// @line: bm_richards.py:266:4
pub fn new_device_task(i i64, p i64, w ?Packet, s TaskState, r &DeviceTaskRec) &DeviceTask {
    mut self := &DeviceTask{}
    self.Task_Impl = new_task_impl(i, p, w, s, r)
    return &self
}
// @line: bm_richards.py:270:4
pub fn (self DeviceTask) py_fn(mut pkt ?Packet, r TaskRec) ?Task {
    mut d := (r as DeviceTaskRec)
    if pkt == none {
        pkt = d.pending
        if pkt == none {
            return self.wait_task()
        } else {
            d.pending = Any(NoneType{})
            return self.qpkt(pkt)
        }
    } else {
        d.pending = pkt
        if py_bool(tracing) {
            trace(pkt.datum)
        }
        return self.hold()
    }
}
// @line: bm_richards.py:288:4
pub fn new_handler_task(i i64, p i64, w ?Packet, s TaskState, r &HandlerTaskRec) &HandlerTask {
    mut self := &HandlerTask{}
    self.Task_Impl = new_task_impl(i, p, w, s, r)
    return &self
}
// @line: bm_richards.py:292:4
pub fn (self HandlerTask) py_fn(pkt ?Packet, r TaskRec) ?Task {
    mut h := (r as HandlerTaskRec)
    if pkt != none {
        if pkt.kind == k_work {
            h.work_in_add(pkt)
        } else {
            h.device_in_add(pkt)
        }
    }
    mut work := h.work_in
    if work == none {
        return self.wait_task()
    }
    count := work.datum
    if count >= bufsize {
        h.work_in = work.link
        return self.qpkt(work)
    }
    mut dev := h.device_in
    if dev == none {
        return self.wait_task()
    }
    h.device_in = dev.link
    dev.datum = py_subscript(work.data, count)
    work.datum = count + 1
    return self.qpkt(dev)
}
// @line: bm_richards.py:321:4
pub fn new_idle_task(i i64, p i64, w i64, s TaskState, r &IdleTaskRec) &IdleTask {
    mut self := &IdleTask{}
    self.Task_Impl = new_task_impl(i, 0, none, s, r)
    return &self
}
// @line: bm_richards.py:325:4
pub fn (self IdleTask) py_fn(pkt ?Packet, r TaskRec) ?Task {
    mut i := (r as IdleTaskRec)
    i.count -= 1
    if i.count == 0 {
        return self.hold()
    } else if i.control & 1 == 0 {
        i.control = int(math.floor(f64(i.control) / f64(2)))
        return self.release(i_deva)
    } else {
        i.control = math.floor(i.control / 2) ^ 53256
        return self.release(i_devb)
    }
}
// @line: bm_richards.py:346:4
pub fn new_work_task(i i64, p i64, w ?Packet, s TaskState, r &WorkerTaskRec) &WorkTask {
    mut self := &WorkTask{}
    self.Task_Impl = new_task_impl(i, p, w, s, r)
    return &self
}
// @line: bm_richards.py:350:4
pub fn (self WorkTask) py_fn(mut pkt ?Packet, r TaskRec) ?Task {
    mut w := (r as WorkerTaskRec)
    if pkt == none {
        return self.wait_task()
    }
    dest := 0
    mut dest := ?i64(none)
    if w.destination == i_handlera {
        dest = ?i64(i_handlerb)
    } else {
        dest = ?i64(i_handlera)
    }
    w.destination = dest
    pkt.ident = dest
    pkt.datum = 0
    mut i := 0
    for i < bufsize {
        w.count += 1
        if w.count > 26 {
            w.count = 1
        }
        pkt.data[i] = a + w.count - 1
        i += 1
    }
    return self.qpkt(pkt)
}
// @line: bm_richards.py:376:0
pub fn schedule() {
    mut t := task_work_area.task_list
    for t != none {
        if py_bool(tracing) {
            println('tcb = ${t.ident}')
        }
        if py_bool(t.is_task_holding_or_waiting()) {
            t = t.link
        } else {
            if py_bool(tracing) {
                trace(u8(int('0'[0]) + t.ident).ascii_str())
            }
            t = t.run_task()
        }
    }
}
// @line: bm_richards.py:392:4
pub fn (self Richards) run(iterations i64) bool {
    for i in 0..iterations {
        task_work_area.hold_count = 0
        task_work_area.qpkt_count = 0
        new_idle_task(i_idle, 1, 10000, new_task_state_impl().running(), new_idle_task_rec())
        mut wkq := new_packet(none, 0, k_work)
        wkq = new_packet(wkq, 0, k_work)
        new_work_task(i_work, 1000, wkq, new_task_state_impl().waiting_with_packet(), new_worker_task_rec())
        wkq = new_packet(none, i_deva, k_dev)
        wkq = new_packet(wkq, i_deva, k_dev)
        wkq = new_packet(wkq, i_deva, k_dev)
        new_handler_task(i_handlera, 2000, wkq, new_task_state_impl().waiting_with_packet(), new_handler_task_rec())
        wkq = new_packet(none, i_devb, k_dev)
        wkq = new_packet(wkq, i_devb, k_dev)
        wkq = new_packet(wkq, i_devb, k_dev)
        new_handler_task(i_handlerb, 3000, wkq, new_task_state_impl().waiting_with_packet(), new_handler_task_rec())
        wkq = none
        new_device_task(i_deva, 4000, wkq, new_task_state_impl().waiting(), new_device_task_rec())
        new_device_task(i_devb, 5000, wkq, new_task_state_impl().waiting(), new_device_task_rec())
        schedule()
        if task_work_area.hold_count == 9297 && task_work_area.qpkt_count == 23246 {
        } else {
            return false
        }
    }
    return true
}
// @benchmarking.benchmark()
// @line: bm_richards.py:433:0
pub fn richards() {
    richards := &Richards{}
    for i in 0..3 {
        assert py_bool(richards__run(1))
    }
}

fn init() {
    // based on a Java version:
    //  Based on original version written in BCPL by Dr Martin Richards
    //  in 1981 at Cambridge University Computer Laboratory, England
    //  and a C++ version derived from a Smalltalk version written by
    //  L Peter Deutsch.
    //  Java version:  Copyright (C) 1995 Sun Microsystems, Inc.
    //  Translation from C++, Mario Wolczko
    //  Outer loop added by Alex Jacoby
    // @line: bm_richards.py:25:0
    // @line: bm_richards.py:26:0
    // @line: bm_richards.py:27:0
    // @line: bm_richards.py:28:0
    // @line: bm_richards.py:29:0
    // @line: bm_richards.py:30:0
    // @line: bm_richards.py:33:0
    // @line: bm_richards.py:34:0
    // @line: bm_richards.py:38:0
    bufsize_range = py_range(bufsize)
    // @line: bm_richards.py:40:0
    tracing = false
    // @line: bm_richards.py:155:0
    layout = 0
    // @line: bm_richards.py:156:0
    // @line: bm_richards.py:168:0
    task_work_area = new_task_work_area()
    // @line: bm_richards.py:182:0
    a = int('A'[0])
    // @line: bm_richards.py:341:0
}
