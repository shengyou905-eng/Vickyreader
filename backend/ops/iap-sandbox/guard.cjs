const fs = require('node:fs');
const os = require('node:os');
const { execFileSync } = require('node:child_process');
const root = '/home/ubuntu/apps/zhidu-iap-sandbox';
const names = ['zhidu-iap-sandbox-api', 'zhidu-iap-sandbox-init',
  'zhidu-iap-sandbox-deps', 'zhidu-iap-sandbox-postgres'];
let previous;
let busySamples = 0;
let checking = false;

async function check() {
  if (checking) return;
  checking = true;
  try {
    const memory = fs.readFileSync('/proc/meminfo', 'utf8');
    const availableMiB = Number(memory.match(/^MemAvailable:\s+(\d+)/m)[1]) / 1024;
    const disk = fs.statfsSync(root);
    const diskFreeGiB = disk.bavail * disk.bsize / 1024 ** 3;
    const cpu = os.cpus().reduce((sum, core) => {
      sum.idle += core.times.idle;
      sum.total += Object.values(core.times).reduce((a, b) => a + b, 0);
      return sum;
    }, { idle: 0, total: 0 });
    const cpuBusy = previous ? 1 - (cpu.idle - previous.idle) / (cpu.total - previous.total) : 0;
    previous = cpu;
    busySamples = cpuBusy > 0.95 ? busySamples + 1 : 0;
    const response = await fetch('http://127.0.0.1:3000/api/health', {
      signal: AbortSignal.timeout(4000), redirect: 'error',
    });
    const health = await response.json();
    if (!response.ok || health.status !== 'ok' || health.env !== 'production') throw new Error('production_health');
    if (availableMiB < 384) throw new Error('memory_pressure');
    if (diskFreeGiB < 5) throw new Error('disk_pressure');
    if (busySamples >= 6) throw new Error('sustained_cpu_pressure');
    fs.writeFileSync(root + '/guard-status.json', JSON.stringify({
      checkedAt: new Date().toISOString(), healthy: true,
      availableMiB: Math.round(availableMiB), diskFreeGiB: +diskFreeGiB.toFixed(2),
      cpuBusyPercent: Math.round(cpuBusy * 100),
    }), { mode: 0o600 });
  } catch (error) {
    const reason = ['production_health', 'memory_pressure', 'disk_pressure', 'sustained_cpu_pressure']
      .includes(error.message) ? error.message : 'health_check_unavailable';
    fs.writeFileSync(root + '/STOPPED', reason, { mode: 0o600 });
    for (const name of names) {
      try { execFileSync('docker', ['stop', '--time', '5', name], { stdio: 'ignore', timeout: 15000 }); } catch (_) {}
    }
    fs.writeFileSync(root + '/guard-status.json', JSON.stringify({
      checkedAt: new Date().toISOString(), healthy: false, reason, stoppedSandbox: true,
    }), { mode: 0o600 });
    console.error('Sandbox stopped by safety guard: ' + reason);
    process.exit(1);
  } finally { checking = false; }
}
check();
setInterval(check, 5000);
