using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;

using ASC.Api.Core;
using ASC.Common;
using ASC.Common.Caching;
using ASC.Common.DependencyInjection;
using ASC.Common.Utils;
using ASC.Webhooks.Core;

using Autofac;
using Autofac.Extensions.DependencyInjection;

using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

using StackExchange.Redis.Extensions.Core.Configuration;
using StackExchange.Redis.Extensions.Newtonsoft;

namespace ASC.Webhooks.Service
{
    public class Program
    {
        public async static Task Main(string[] args)
        {
            var host = CreateHostBuilder(args).Build();

            await host.RunAsync();
        }

        public static IHostBuilder CreateHostBuilder(string[] args) =>
            Host.CreateDefaultBuilder(args)
                .UseSystemd()
                .UseWindowsService()
                .UseServiceProviderFactory(new AutofacServiceProviderFactory())
                .ConfigureWebHostDefaults(webBuilder => webBuilder.UseStartup<BaseWorkerStartup>())
                .ConfigureAppConfiguration((hostContext, config) =>
                {
                    var buided = config.Build();
                    var path = buided["pathToConf"];
                    if (!Path.IsPathRooted(path))
                    {
                        path = Path.GetFullPath(CrossPlatform.PathCombine(hostContext.HostingEnvironment.ContentRootPath, path));
                    }
                    config.SetBasePath(path);
                    var env = hostContext.Configuration.GetValue("ENVIRONMENT", "Production");
                    config
                        .AddInMemoryCollection(new Dictionary<string, string>
                            {
                                {"pathToConf", path }
                            }
                        )
                        .AddJsonFile("appsettings.json")
                        .AddJsonFile($"appsettings.{env}.json", true)
                        .AddJsonFile($"appsettings.services.json", true)
                        .AddJsonFile("storage.json")
                        .AddJsonFile("kafka.json")
                        .AddJsonFile($"kafka.{env}.json", true)
                        .AddJsonFile("redis.json")
                        .AddJsonFile($"redis.{env}.json", true)
                        .AddEnvironmentVariables()
                        .AddCommandLine(args);
                })
                .ConfigureServices((hostContext, services) =>
                {
                    services.AddMemoryCache();

                    var diHelper = new DIHelper(services);

                    var redisConfiguration = hostContext.Configuration.GetSection("Redis").Get<RedisConfiguration>();
                    var kafkaConfiguration = hostContext.Configuration.GetSection("kafka").Get<KafkaSettings>();

                    if (kafkaConfiguration != null)
                    {
                        diHelper.TryAdd(typeof(ICacheNotify<>), typeof(KafkaCache<>));
                    }
                    else if (redisConfiguration != null)
                    {
                        diHelper.TryAdd(typeof(ICacheNotify<>), typeof(RedisCache<>));

                        services.AddStackExchangeRedisExtensions<NewtonsoftSerializer>(redisConfiguration);
                    }
                    else
                    {
                        diHelper.TryAdd(typeof(ICacheNotify<>), typeof(MemoryCacheNotify<>));
                    }

                    diHelper.TryAdd<DbWorker>();

                    services.AddHostedService<WebhookHostedService>();
                    diHelper.TryAdd<WebhookHostedService>();

                })
                .ConfigureContainer<ContainerBuilder>((context, builder) =>
                {
                    builder.Register(context.Configuration, false, false);
                })
                .ConfigureNLogLogging();
    }
}