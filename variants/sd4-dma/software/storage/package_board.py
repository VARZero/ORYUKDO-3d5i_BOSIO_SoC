"""Package only an audited implementation matching the current local source."""
from pathlib import Path
import hashlib,json,re,shutil,sys
root=Path(__file__).resolve().parents[2]
board=Path(sys.argv[1]).resolve();out=Path(sys.argv[2]).resolve()
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
def txt(p):return p.read_text(errors='replace')
def host(p):
 return Path('/mnt/'+p[0].lower()+p[2:].replace('\\','/')) if sys.platform!='win32' and p[1]==':' else Path(p)
runner=txt(board.parent/(board.name+'_runner.log'))
assert 'PASS KFB_BOSIO_BOARD_ROUTE ' in runner,'Implementation did not complete successfully'
log=txt(board/'route_console.log')
io_log=txt(board/'io_coverage_console.log')
assert 'PASS CURRENT_BOARD_IO_COVERAGE_INSPECTION' in io_log,'Missing final I/O coverage review'
for marker in ('PASS KFB_BOARD_ROUTED_AUDIT','PASS NATIVE_SD_PAD_AND_PHASE_TIMING_AUDIT'):
 assert marker in log,marker
for name,digest in json.loads(txt(board/'source_manifest.json')).items():
 assert sha(host(name))==digest,'Current source differs: '+name
for name,digest in json.loads(txt(board/'route/implementation_inputs.json'))['input_hashes'].items():
 assert sha(host(name))==digest,'Implementation input differs: '+name
constraints=txt(board/'route/resolved_constraints.xdc')
uncertainty_lines=[line for line in constraints.splitlines() if line.startswith('set_clock_uncertainty -setup 0.300 ')]
for clock in ('cpu_raw','clk_pll_i'):
 assert any(re.search(r'\b'+clock+r'\b',line) for line in uncertainty_lines),'Clock uncertainty changed: '+clock
critical_warnings=sorted(set(re.findall(r'^CRITICAL WARNING: (.+)',log,re.M)))
assert all('[Project 1-1108]' in line for line in critical_warnings),'Unreviewed Vivado critical warning'
timing=txt(board/'route/timing_routed.rpt')
match=re.search(r'WNS\(ns\).*?\n\s*-+[^\n]*\n\s*([^\n]+)',timing,re.S)
assert match,'Missing timing summary'
row=match[1].split()
wns,tns,whs,ths,wpws=map(float,(row[0],row[1],row[4],row[5],row[8]))
assert min(wns,whs,wpws)>=0 and tns==0 and ths==0,'Routed timing violation'
drc=txt(board/'route/drc.rpt');known={'BUFC-1':4,'REQP-1709':1};warnings={}
for rule,severity,count in re.findall(r'^\|\s*([A-Z][A-Z0-9]+-\d+)\s*\|\s*([^|]+?)\s*\|[^|]*\|\s*(\d+)\s*\|',drc,re.M):
 assert severity.strip()=='Warning' and rule in known and int(count)<=known[rule],(rule,severity,count)
 warnings[rule]=int(count)
assert not re.search(r'\|\s*(Error|Critical Warning)\s*\|',drc)
total=re.search(r'Violations found:\s*(\d+)',drc)
assert total and int(total[1])==sum(warnings.values()),'Unparsed DRC violation'
cdc=txt(board/'route/cdc.rpt')
assert not re.search(r'^CDC-\d+\s+(Warning|Critical)\s+[1-9]',cdc,re.M),'CDC warning/critical'
util=txt(board/'route/utilization.rpt')
resources={}
for label,key in [('Slice LUTs','lut'),('Slice Registers','ff'),('Block RAM Tile','bram_tiles'),('DSPs','dsp'),('Slice','occupied_slices')]:
 m=re.search(r'^\|\s*'+re.escape(label)+r'\*?\s*\|\s*([0-9.,]+)',util,re.M)
 assert m,label
 resources[key]=float(m[1].replace(',',''))
bit=board/'route/ORYUKDO-Gen3-BOSIO-KFB.bit'
assert bit.is_file() and bit.stat().st_size>100000
image=out/'ORYUKDO-KFB-SD4-DMA-v1.img'
image_sha=sha(image)
status=json.loads(txt(root/'validation/status.json'))
assert all(check['pass_marker'] for check in status['checks'].values()),'Regression failure/missing log'
assert status['actual_image_loader']['current_rtl_matches'],'Loader RTL differs from tested source'
assert status['full_board']['source_match'] and status['full_board']['route_pass_marker'],'Board evidence is stale'
for evidence in ('actual_image_loader.json','qemu_shell/result.json'):
 assert json.loads(txt(root/'validation'/evidence))['image_sha256']==image_sha,'Image differs from tested payload'
out.mkdir(parents=True,exist_ok=True)
target=out/'ORYUKDO-KFB-SD4-DMA-v1.bit';shutil.copy2(bit,target)
report_dir=out/'board_reports';report_dir.mkdir(exist_ok=True)
for p in (board/'route').iterdir():
 if p.is_file() and p.suffix in ('.rpt','.tsv','.json','.xdc'):shutil.copy2(p,report_dir/p.name)
shutil.copy2(board/'source_manifest.json',report_dir/'source_manifest.json')
shutil.copy2(board/'route_console.log',report_dir/'route_console.log')
shutil.copy2(board/'synth_console.log',report_dir/'synth_console.log')
(report_dir/'synth').mkdir(exist_ok=True)
for p in (board/'synth').glob('*.rpt'):shutil.copy2(p,report_dir/'synth'/p.name)
shutil.copy2(board/'io_coverage/io_timing_coverage.rpt',report_dir/'io_timing_coverage.rpt')
shutil.copy2(board/'io_coverage_console.log',report_dir/'io_coverage_console.log')
report={'result':'PASS_IMPLEMENTATION_HARDWARE_UNTESTED','source_directory':str(root),
 'implementation_directory':str(board),'part':'xc7a200tfbg484-2',
 'resources':resources,'timing_ns':{'wns':wns,'tns':tns,'whs':whs,'ths':ths,'wpws':wpws},
 'clock_targets_mhz':{'cpu':50,'fabric':100,'sd_max':25,'pixel':74.25,'serializer':371.25},
 'drc_known_mig_warnings':warnings,'cdc_warning_critical':0,
 'vivado_raw_critical_warnings':critical_warnings,
 'cpu_fabric_setup_uncertainty_ns':0.3,
 'io_coverage_limits':{'no_external_output_delay':['ddr3_reset_n','hdmi_clk_p','hdmi_data_p[0]','hdmi_data_p[1]','hdmi_data_p[2]'],
  'asynchronous_input_max_delay_only':['gp_i2c_scl','gp_i2c_sda','gp_spi_miso','gp_uart_rx','sensor_scl','sensor_sda','uart_rx'],
  'async_reset_false_path':'rst_n','generated_output_clock':'sd_dclk'},
 'bitstream':target.name,'bitstream_sha256':sha(target),
 'image':image.name,'image_sha256':image_sha,'hardware_tested':False,
 'source_manifest_sha256':sha(board/'source_manifest.json')}
report['routed_checkpoint_sha256']=sha(board/'route/routed.dcp')
report['io_inspection_script_sha256']=sha(root/'software/storage/inspect_io.tcl')
report['internal_clock_setup_slack_ns']={}
for clock in ('cpu_raw','clk_pll_i','pixel_raw','serial_raw'):
 m=re.search(r'Slack \(MET\)\s*:\s*([0-9.]+)ns',txt(board/'route'/('timing_'+clock+'.rpt')))
 if m:report['internal_clock_setup_slack_ns'][clock]=float(m[1])
(out/'board_manifest.json').write_text(json.dumps(report,indent=2)+'\n')
(root/'validation/board_implementation.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
