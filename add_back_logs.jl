    using Downloads
    using JSON
    using Feather
    using ProgressMeter

    short_sha(str) = str[1:7]

    function add_back_logs(path)
        # Primary
        json_primary = JSON.parsefile(joinpath(path, "primary.json"))
        sha_primary = short_sha(json_primary["build"]["sha"])

        json_against = JSON.parsefile(joinpath(path, "against.json"))
        sha_against = short_sha(json_against["build"]["sha"])

        base_url = "https://s3.amazonaws.com/julialang-reports/nanosoldier/pkgeval/by_hash/$(sha_primary)_vs_$(sha_against)/"

        add_back_log(path, base_url, :primary)
        add_back_log(path, base_url, :against)
    end

    function add_back_log(path, base_url, type)
        df = Feather.read(joinpath(path, "$type.feather"))
        logs = download_logs(df, base_url, type)
        logs = String[logs[pkg] for pkg in df.package]
        df.log = logs
        Feather.write(joinpath(path, "$(type)_log.feather"), df)
    end

    function download_logs(df, base_url, type)
        queue = copy(df.package)
        d = Dict{String, String}()
        p = Progress(length(queue), 1)   # minimum update interval: 1 second
        l = ReentrantLock()
        @sync for _ in 1:16
            @async while !isempty(queue)            
                package = popfirst!(queue)
                output = IOBuffer()
                r = Downloads.request(string(base_url, string(package, ".", type, ".log")) ;output)
                if r.status !== 200
                    @warn "Failed to get log for package $(repr(package)) from url $(repr(base_url))"
                    d[package] = ""
                else
                    d[package] = String(take!(output))
                end
                lock(l) do
                    next!(p)
                end
            end
        end
        return d
    end
