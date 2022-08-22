﻿// (c) Copyright Ascensio System SIA 2010-2022
//
// This program is a free software product.
// You can redistribute it and/or modify it under the terms
// of the GNU Affero General Public License (AGPL) version 3 as published by the Free Software
// Foundation. In accordance with Section 7(a) of the GNU AGPL its Section 15 shall be amended
// to the effect that Ascensio System SIA expressly excludes the warranty of non-infringement of
// any third-party rights.
//
// This program is distributed WITHOUT ANY WARRANTY, without even the implied warranty
// of MERCHANTABILITY or FITNESS FOR A PARTICULAR  PURPOSE. For details, see
// the GNU AGPL at: http://www.gnu.org/licenses/agpl-3.0.html
//
// You can contact Ascensio System SIA at Lubanas st. 125a-25, Riga, Latvia, EU, LV-1021.
//
// The  interactive user interfaces in modified source and object code versions of the Program must
// display Appropriate Legal Notices, as required under Section 5 of the GNU AGPL version 3.
//
// Pursuant to Section 7(b) of the License you must retain the original Product logo when
// distributing the program. Pursuant to Section 7(e) we decline to grant you any rights under
// trademark law for use of our trademarks.
//
// All the Product's GUI elements, including illustrations and icon sets, as well as technical writing
// content are licensed under the terms of the Creative Commons Attribution-ShareAlike 4.0
// International. See the License terms at http://creativecommons.org/licenses/by-sa/4.0/legalcode

namespace ASC.Api.Core.Extensions;

public static class HostBuilderExtension
{
    public static IHostBuilder ConfigureDefault(this IHostBuilder hostBuilder, string[] args,
        Action<HostBuilderContext, IConfigurationBuilder, IHostEnvironment, string> configureApp = null,
        Action<HostBuilderContext, IServiceCollection, DIHelper> configureServices = null)
    {
        hostBuilder.UseSystemd();
        hostBuilder.UseWindowsService();
        hostBuilder.UseServiceProviderFactory(new AutofacServiceProviderFactory());
        hostBuilder.ConfigureDefaultAppConfiguration(args, configureApp);
        hostBuilder.ConfigureDefaultServices(configureServices);
        hostBuilder.ConfigureNLogLogging();

        return hostBuilder;
    }

    public static IHostBuilder ConfigureDefaultAppConfiguration(this IHostBuilder hostBuilder, string[] args, Action<HostBuilderContext, IConfigurationBuilder, IHostEnvironment, string> configureDelegate = null)
    {
        hostBuilder.ConfigureAppConfiguration((hostContext, config) =>
        {
            var buildedConfig = config.Build();

            var path = buildedConfig["pathToConf"];

            if (!Path.IsPathRooted(path))
            {
                path = Path.GetFullPath(CrossPlatform.PathCombine(hostContext.HostingEnvironment.ContentRootPath, path));
            }

            var env = hostContext.HostingEnvironment;

            config.SetBasePath(path);
            config.AddJsonFile("appsettings.json")
                  .AddJsonFile($"appsettings.{env.EnvironmentName}.json", true)
                  .AddJsonFile("storage.json")
                  .AddJsonFile("kafka.json")
                  .AddJsonFile($"kafka.{env.EnvironmentName}.json", true)
                  .AddJsonFile("rabbitmq.json")
                  .AddJsonFile($"rabbitmq.{env.EnvironmentName}.json", true)
                  .AddJsonFile("redis.json")
                  .AddJsonFile($"redis.{env.EnvironmentName}.json", true);

            configureDelegate?.Invoke(hostContext, config, env, path);

            config.AddEnvironmentVariables()
                  .AddCommandLine(args)
                  .AddInMemoryCollection(new Dictionary<string, string>
                  {
                      {"pathToConf", path }
                  });
        });

        return hostBuilder;
    }

    public static IHostBuilder ConfigureDefaultServices(this IHostBuilder hostBuilder, Action<HostBuilderContext, IServiceCollection, DIHelper> configureDelegate)
    {
        hostBuilder.ConfigureServices((hostContext, services) =>
        {
            services.AddMemoryCache();

            services.AddDistributedCache(hostContext.Configuration);
            services.AddEventBus(hostContext.Configuration);
            services.AddDistributedTaskQueue();
            services.AddCacheNotify(hostContext.Configuration);

            var diHelper = new DIHelper(services);

            configureDelegate?.Invoke(hostContext, services, diHelper);
        });

        return hostBuilder;
    }
}