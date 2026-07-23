#!/usr/bin/env python3
"""
Run GliderTools QC on L0 data and produce comparison plots.
Usage: python pipeline/run_glidertools_comparison.py "path/to/L0.nc"
"""
import sys, os, numpy as np, xarray as xr
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt

try:
    import glidertools as gt
    print(f"GliderTools version: {gt.__version__}")
except ImportError:
    print("ERROR: pip install glidertools"); sys.exit(1)

def main():
    if len(sys.argv) < 2:
        print("Usage: python run_glidertools_comparison.py <L0.nc> [output_dir]"); sys.exit(1)

    l0_path = sys.argv[1]
    out_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(l0_path), "..", "output", "plots")
    os.makedirs(out_dir, exist_ok=True)

    ds = xr.open_dataset(l0_path)
    dives = ds["profile_index"].values
    depth = ds["depth"].values
    time = ds["time"].values
    print(f"Loaded: {len(time):,} obs, {len(np.unique(dives[np.isfinite(dives)]))} profiles, max depth {np.nanmax(depth):.0f}m")

    temp = ds["potential_temperature"].values if "potential_temperature" in ds else ds["temperature"].values if "temperature" in ds else None
    sal = ds["salinity"].values if "salinity" in ds else None
    chl = ds["chlorophyll"].values if "chlorophyll" in ds else None
    bbp = ds["backscatter_700"].values if "backscatter_700" in ds else None

    # --- GT Physics ---
    print("\n--- GT Physics QC ---")
    temp_gt = sal_gt = None
    if temp is not None:
        try:
            temp_gt = gt.processing.calc_physics(temp, dives, depth)
            print(f"  Temp: {np.sum(np.isfinite(temp)):,} -> {np.sum(np.isfinite(temp_gt)):,}")
        except Exception as e:
            print(f"  Temp failed: {e}"); temp_gt = temp.copy()
    if sal is not None:
        try:
            sal_gt = gt.processing.calc_physics(sal, dives, depth)
            print(f"  Sal:  {np.sum(np.isfinite(sal)):,} -> {np.sum(np.isfinite(sal_gt)):,}")
        except Exception as e:
            print(f"  Sal failed: {e}"); sal_gt = sal.copy()

    # --- GT Optics ---
    print("\n--- GT Optics QC ---")
    bbp_gt = chl_gt = None
    if bbp is not None and temp is not None and sal is not None:
        try:
            bbp_gt = gt.processing.calc_backscatter(bbp, temp, sal, dives, depth, wavelength=700)
            print(f"  BBP: {np.sum(np.isfinite(bbp)):,} -> {np.sum(np.isfinite(bbp_gt)):,}")
        except Exception as e:
            print(f"  BBP failed: {e}"); bbp_gt = bbp.copy() if bbp is not None else None
    if chl is not None and bbp_gt is not None:
        try:
            lat = ds["latitude"].values if "latitude" in ds else np.full(len(time), 10.0)
            lon = ds["longitude"].values if "longitude" in ds else np.full(len(time), 67.0)
            chl_gt = gt.processing.calc_fluorescence(chl, bbp_gt, dives, depth, time, lat, lon)
            print(f"  Chl: {np.sum(np.isfinite(chl)):,} -> {np.sum(np.isfinite(chl_gt)):,}")
        except Exception as e:
            print(f"  Chl failed: {e}"); chl_gt = chl.copy()

    # --- Grid + Plot ---
    print("\n--- GT Gridding ---")
    def gplot(data, name, cmap, units, max_d=None, fname=None):
        if data is None: return
        try:
            grid, d_g, d_i = gt.mapping.grid_data(dives, depth, data, bins=1, how="mean")
            if max_d:
                m = d_g <= max_d; grid = grid[:, m]; d_g = d_g[m]
            else:
                max_d = d_g[-1]
            fin = grid[np.isfinite(grid)]
            if len(fin) == 0: return
            fig, ax = plt.subplots(figsize=(14, 5))
            ax.pcolormesh(np.arange(grid.shape[0]+1)-0.5, np.append(d_g-0.5, d_g[-1]+0.5),
                          grid.T, cmap=cmap, vmin=np.nanmin(fin), vmax=np.nanmax(fin), shading="flat")
            ax.set_ylim(max_d, 0); ax.set_ylabel("Depth [m]"); ax.set_xlabel("Profile #")
            ax.set_title(f"GliderTools: {name}"); plt.colorbar(ax.collections[0], ax=ax, label=f"[{units}]")
            plt.tight_layout()
            f = fname or f"GT_{name.lower().replace(' ','_')}.png"
            plt.savefig(os.path.join(out_dir, f), dpi=150, bbox_inches="tight"); plt.close()
            print(f"  Saved: {f}")
        except Exception as e:
            print(f"  {name} failed: {e}")

    gplot(temp_gt, "Temperature (GT QC)", "RdYlBu_r", "C")
    gplot(sal_gt, "Salinity (GT QC)", "viridis", "PSU")
    gplot(chl_gt, "Chlorophyll (GT QC)", "YlGn", "mg/m3", max_d=200)
    gplot(bbp_gt, "Backscatter (GT QC)", "inferno", "m-1", max_d=200)
    gplot(temp, "Temperature (raw)", "RdYlBu_r", "C", fname="GT_temp_raw.png")
    gplot(chl, "Chlorophyll (raw)", "YlGn", "mg/m3", max_d=200, fname="GT_chl_raw.png")

    # Summary
    print("\n--- Summary ---")
    print(f"  {'Var':<12} {'Raw':>8} {'GT':>8} {'%':>6}")
    for n, r, g in [("Temp",temp,temp_gt),("Sal",sal,sal_gt),("Chl",chl,chl_gt),("BBP",bbp,bbp_gt)]:
        if r is not None and g is not None:
            nr, ng = int(np.sum(np.isfinite(r))), int(np.sum(np.isfinite(g)))
            print(f"  {n:<12} {nr:>8,} {ng:>8,} {100*ng/max(nr,1):>5.1f}%")
    ds.close()
    print(f"\nDone. Plots in: {out_dir}")

if __name__ == "__main__":
    main()
