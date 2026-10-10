#!/usr/bin/env python3
"""Real XTest drag supplement for qa_native_regression.py; no game API calls."""
import argparse, ctypes as C, json, time
p=argparse.ArgumentParser();p.add_argument('--display',required=True);p.add_argument('--start',required=True);p.add_argument('--end',required=True);a=p.parse_args()
x=C.CDLL('libX11.so.6');t=C.CDLL('libXtst.so.6')
x.XOpenDisplay.argtypes=[C.c_char_p];x.XOpenDisplay.restype=C.c_void_p
x.XFlush.argtypes=[C.c_void_p];x.XCloseDisplay.argtypes=[C.c_void_p]
t.XTestFakeMotionEvent.argtypes=[C.c_void_p,C.c_int,C.c_int,C.c_int,C.c_ulong];t.XTestFakeButtonEvent.argtypes=[C.c_void_p,C.c_uint,C.c_int,C.c_ulong]
d=x.XOpenDisplay(a.display.encode())
if not d:raise RuntimeError('Cannot open the existing isolated Xorg display')
start=tuple(map(int,a.start.split(',')));end=tuple(map(int,a.end.split(',')))
def move(point):t.XTestFakeMotionEvent(d,-1,*point,0);x.XFlush(d);time.sleep(.05)
try:
 move(start);t.XTestFakeButtonEvent(d,1,1,0);x.XFlush(d);time.sleep(.08)
 for i in range(1,13):move(tuple(round(s+(e-s)*i/12) for s,e in zip(start,end)))
 t.XTestFakeButtonEvent(d,1,0,0);x.XFlush(d);time.sleep(.15)
 print(json.dumps({'method':'libXTest OS mouse drag','display':a.display,'from':start,'to':end,'held_motion_events':12}))
finally:x.XCloseDisplay(d)
