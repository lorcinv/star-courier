extends RefCounted
## Original, bounded procedural shop bell. No external sample or saved file.
static func make_stream() -> AudioStreamWAV:
 const RATE:int=22050
 const DURATION:float=.85
 var sample_count:int=int(RATE*DURATION)
 var data:=PackedByteArray();data.resize(sample_count*2)
 for sample in sample_count:
  var t:float=float(sample)/RATE
  var value:float=0.0
  for strike in 2:
   var age:float=t-float(strike)*.16
   if age<0:continue
   var base:float=1174.66 if strike==0 else 1567.98
   var envelope:float=(1.0-exp(-age*260.0))*exp(-age*6.5)
   value+=(sin(TAU*base*age)+.32*sin(TAU*base*2.76*age)+.13*sin(TAU*base*5.4*age))*envelope*.23
  data.encode_s16(sample*2,clampi(roundi(value*32767),-32768,32767))
 var stream:=AudioStreamWAV.new();stream.format=AudioStreamWAV.FORMAT_16_BITS;stream.mix_rate=RATE;stream.stereo=false;stream.data=data
 return stream
